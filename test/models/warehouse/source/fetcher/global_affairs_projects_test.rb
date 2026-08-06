require "test_helper"

class Warehouse::Source::Fetcher::GlobalAffairsProjectsTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:status, :chunks) do
    def each(&block)
      chunks.each(&block)
    end
  end

  class FakeHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def get(url, **options)
      @requests << { url: url, **options }
      @responses.fetch(url)
    end
  end

  STATUS_2_URL = "https://example.test/status-2.xml".freeze
  STATUS_4_URL = "https://example.test/status-4.xml".freeze

  test "streams all activity files into canonical IATI project rows" do
    http = FakeHttp.new(
      STATUS_2_URL => response(iati_file(activity(id: "CA-3-A100", status: "2", title: "Implementation project")), chunks: 3),
      STATUS_4_URL => response(iati_file(activity(id: "CA-3-A200", status: "4", title: "Closed project")), chunks: 2)
    )

    download = Warehouse::Source::Fetcher::GlobalAffairsProjects.new(
      urls: { "2" => STATUS_2_URL, "4" => STATUS_4_URL }, http: http
    ).call
    rows = CSV.new(download.io, headers: true).map(&:to_h)

    assert_equal %w[CA-3-A100 CA-3-A200], rows.pluck("external_id")
    assert_equal [
      { url: STATUS_2_URL, stream: true },
      { url: STATUS_4_URL, stream: true }
    ], http.requests
    assert_equal Digest::SHA256.file(download.io.path).hexdigest, download.checksum

    row = rows.first
    assert_equal "Implementation project", row.fetch("title")
    assert_equal "English description", row.fetch("description")
    assert_equal "2020-02-03", row.fetch("start_date")
    assert_equal "2025-04-05", row.fetch("end_date")
    assert_equal "1250.5", row.fetch("commitment_amount")
    assert_equal "CAD", row.fetch("currency")
    assert_equal "Partner One", JSON.parse(row.fetch("implementing_organizations")).sole.fetch("name")
    assert_equal "KE", JSON.parse(row.fetch("countries")).sole.fetch("code")
    assert_equal "11110", JSON.parse(row.fetch("sectors")).sole.fetch("code")
    assert_equal "Results achieved", JSON.parse(row.fetch("results")).sole.fetch("title")
    assert_equal "https://example.test/projects/A100", row.fetch("detail_url")
    assert_equal STATUS_2_URL, row.fetch("source_url")
    refute_includes JSON.parse(row.fetch("source_fields")), "last_updated_datetime"
  ensure
    download&.io&.close!
  end

  test "rejects identifiers duplicated across activity files" do
    http = FakeHttp.new(
      STATUS_2_URL => response(iati_file(activity(id: "CA-3-DUPLICATE"))),
      STATUS_4_URL => response(iati_file(activity(id: "CA-3-DUPLICATE", status: "4")))
    )

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::GlobalAffairsProjects.new(
        urls: [ STATUS_2_URL, STATUS_4_URL ], http: http
      ).call
    end

    assert_match(/Duplicate.*CA-3-DUPLICATE/, error.message)
  end

  test "rejects an activity without an IATI identifier" do
    http = FakeHttp.new(STATUS_2_URL => response(iati_file(activity(id: ""))))

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::GlobalAffairsProjects.new(urls: [ STATUS_2_URL ], http: http).call
    end

    assert_match(/without an identifier/, error.message)
  end

  test "rejects an empty activity file set" do
    http = FakeHttp.new(STATUS_2_URL => response(iati_file("")))

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::GlobalAffairsProjects.new(urls: [ STATUS_2_URL ], http: http).call
    end

    assert_match(/contained no activities/, error.message)
  end

  test "rejects failed downloads" do
    http = FakeHttp.new(STATUS_2_URL => FakeResponse.new(503, [ "unavailable" ]))

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::GlobalAffairsProjects.new(urls: [ STATUS_2_URL ], http: http).call
    end

    assert_match(/HTTP 503/, error.message)
  end

  test "uses a positional XML url as a single-file acquisition" do
    http = FakeHttp.new(STATUS_2_URL => response(iati_file(activity(id: "CA-3-ONE"))))

    download = Warehouse::Source::Fetcher::GlobalAffairsProjects.new(STATUS_2_URL, http: http).call

    assert_equal [ "CA-3-ONE" ], CSV.new(download.io, headers: true).map { |row| row["external_id"] }
    assert_equal [ { url: STATUS_2_URL, stream: true } ], http.requests
  ensure
    download&.io&.close!
  end

  test "the export-wide activity timestamp does not defeat checksum deduplication" do
    build = ->(updated_at) do
      xml = iati_file(activity(id: "CA-3-STABLE", updated_at: updated_at))
      http = FakeHttp.new(STATUS_2_URL => response(xml))
      Warehouse::Source::Fetcher::GlobalAffairsProjects.new(urls: [ STATUS_2_URL ], http: http).call
    end

    first = build.call("2026-08-06T06:32:53-05:00")
    second = build.call("2026-08-07T06:30:00-05:00")

    assert_equal first.io.read, second.io.read
    assert_equal first.checksum, second.checksum
  ensure
    first&.io&.close!
    second&.io&.close!
  end

  private

  def response(body, chunks: 1)
    size = (body.bytesize.to_f / chunks).ceil
    FakeResponse.new(200, body.bytes.each_slice(size).map { |bytes| bytes.pack("C*") })
  end

  def iati_file(contents)
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <iati-activities version="2.03">#{contents}</iati-activities>
    XML
  end

  def activity(id:, status: "2", title: "A project", updated_at: "2026-08-06T06:32:53-05:00")
    <<~XML
      <iati-activity last-updated-datetime="#{updated_at}" default-currency="CAD" humanitarian="0">
        <iati-identifier>#{id}</iati-identifier>
        <reporting-org ref="CA-3" type="10">
          <narrative xml:lang="fr">Affaires mondiales Canada</narrative>
          <narrative xml:lang="en">Global Affairs Canada</narrative>
        </reporting-org>
        <title>
          <narrative xml:lang="fr">Titre français</narrative>
          <narrative xml:lang="en">#{title}</narrative>
        </title>
        <description type="1">
          <narrative xml:lang="fr">Description française</narrative>
          <narrative xml:lang="en">English description</narrative>
        </description>
        <participating-org role="4" type="21" ref="XM-DAC-123">
          <narrative xml:lang="en">Partner One</narrative>
        </participating-org>
        <other-identifier ref="100200" type="A2"/>
        <activity-status code="#{status}"/>
        <activity-date type="1" iso-date="2019-01-01"/>
        <activity-date type="2" iso-date="2020-02-03"/>
        <activity-date type="3" iso-date="2024-03-04"/>
        <activity-date type="4" iso-date="2025-04-05"/>
        <activity-scope code="4"/>
        <recipient-country code="KE" percentage="75.00"/>
        <recipient-region code="298" vocabulary="1" percentage="25.00"/>
        <sector code="11110" vocabulary="1" percentage="100.00"/>
        <policy-marker code="1" vocabulary="1" significance="2"/>
        <collaboration-type code="1"/>
        <default-finance-type code="110"/>
        <default-aid-type code="C01"/>
        <transaction><transaction-type code="2"/><value>1000.50</value></transaction>
        <transaction><transaction-type code="2"/><value>250</value></transaction>
        <transaction><transaction-type code="3"/><value>9999</value></transaction>
        <document-link url="https://example.test/projects/A100" format="text/html">
          <category code="A02"/><language code="en"/>
        </document-link>
        <result type="2">
          <title><narrative xml:lang="en">Results achieved</narrative></title>
          <indicator measure="5">
            <title><narrative xml:lang="en">Households reached</narrative></title>
            <period><period-start iso-date="2024-01-01"/><period-end iso-date="2024-12-31"/><actual value="42"/></period>
          </indicator>
        </result>
      </iati-activity>
    XML
  end
end
