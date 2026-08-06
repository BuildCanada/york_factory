require "test_helper"

class Warehouse::Spending::Scrapers::GlobalAffairsProjectsTest < ActiveJob::TestCase
  XML = <<~XML
    <?xml version="1.0" encoding="utf-8"?>
    <projects>
      <project>
        <projectNumber>CA-3-A020449003</projectNumber>
        <dateModified>2025-03-04T06:33:31</dateModified>
        <title>Program Support Unit</title>
        <description>Support for project delivery.</description>
        <status>Closed</status>
        <start>2008-07-02T00:00:00</start>
        <end>2012-11-21T00:00:00</end>
        <executingAgencyPartner>High Commission of Canada</executingAgencyPartner>
        <maximumContribution>2457111.50</maximumContribution>
        <programName>WGM Africa</programName>
        <aidType>Project-type interventions</aidType>
        <financeType>Aid grant</financeType>
        <countries><country>Cameroon 100.00%</country></countries>
        <DACSectors><DACSectors>Multisector aid 100.00%</DACSectors></DACSectors>
        <participatingOrgs>
          <participatingOrg countryCode="CM">High Commission of Canada</participatingOrg>
        </participatingOrgs>
      </project>
    </projects>
  XML

  setup do
    @source = Warehouse::Source.create!(
      name: "spending_global_affairs_projects",
      url: "https://example.test/projects.xml",
      format: "spending_global_affairs_xml"
    )
    @ingestion = create_ingestion("global-affairs-1")
  end

  test "loads Global Affairs XML and enqueues its ingestion for search" do
    result = nil
    assert_no_enqueued_jobs only: Search::SyncJob do
      assert_enqueued_with(job: Warehouse::SyncSpendingIngestionJob, args: [ @ingestion ]) do
        result = @ingestion.spending_loader.load(body: XML)
      end
    end

    assert_equal 1, result.created
    award = Warehouse::SpendingAward.sole
    assert_equal "CA-3-A020449003", award.external_key
    assert_equal "contribution", award.award_type
    assert_equal "High Commission of Canada", award.recipient_name
    assert_equal 2_457_111.50, award.amount.to_f
    assert_equal "CM", award.country_code
    assert_equal "complete", @ingestion.reload.status
  end

  test "loads canonical IATI CSV produced by the acquisition adapter" do
    csv = CSV.generate do |writer|
      writer << Warehouse::Source::Fetcher::GlobalAffairsProjects::OUTPUT_HEADERS
      writer << [
        "CA-3-A031470001",
        "Common Development Funds",
        "Support for basic social services.",
        JSON.generate([ { "name" => "Sagem Sécurité", "type" => "70" } ]),
        "2002-04-02",
        "2017-12-29",
        "20000000.00",
        "CAD",
        "2",
        "C01",
        "1",
        "110",
        JSON.generate([ { "code" => "ML", "percentage" => "100.00" } ]),
        JSON.generate([]),
        JSON.generate([ { "code" => "11120", "percentage" => "40.00" } ]),
        JSON.generate([ { "code" => "3", "significance" => "1" } ]),
        JSON.generate([
          {
            "type" => "2",
            "title" => "Expected Results",
            "indicators" => [ { "description" => "Managers have more capacity." } ]
          },
          {
            "type" => "2",
            "title" => "Results achieved",
            "indicators" => [ { "description" => "Managers completed training." } ]
          }
        ]),
        "https://example.test/projects/A031470001",
        "https://example.test/status-2.xml",
        JSON.generate({ "reporting_organization" => { "name" => "Global Affairs Canada" } })
      ]
    end

    result = @ingestion.spending_loader.load(body: StringIO.new(csv))

    assert_equal 1, result.created
    award = Warehouse::SpendingAward.sole
    assert_equal "CA-3-A031470001", award.external_key
    assert_equal "Sagem Sécurité", award.recipient_name
    assert_equal 20_000_000, award.amount
    assert_equal "ML", award.country_code
    assert_equal "https://example.test/projects/A031470001", award.source_url
    assert_equal "implementation", award.metadata.fetch("status")
    assert_equal "C01", award.metadata.fetch("aid_type")
    refute_includes award.metadata, "date_modified"
    assert_equal [ "11120 40.00%" ], award.metadata.fetch("sectors")
    assert_equal "11120", award.metadata.fetch("iati_sectors").sole.fetch("code")
    assert_equal "Managers have more capacity.", award.metadata.fetch("expected_results")
    assert_equal "Managers completed training.", award.metadata.fetch("results_achieved")
    assert_equal "Global Affairs Canada", award.metadata.fetch("reporting_organisation")
  end

  test "is idempotent and withdraws missing projects" do
    @ingestion.spending_loader.load(body: XML)
    ingestion2 = create_ingestion("global-affairs-2")

    result = ingestion2.spending_loader.load(body: XML)
    assert_equal 1, result.unchanged
    assert_equal 1, Warehouse::SpendingAward.count

    missing = @source.spending_awards.create!(
      external_key: "CA-3-MISSING",
      award_type: "contribution",
      title: "Project removed from the next snapshot",
      first_seen_at: 1.day.ago,
      last_seen_at: 1.day.ago
    )
    ingestion3 = create_ingestion("global-affairs-3")
    result = ingestion3.spending_loader.load(body: XML)
    assert_equal 1, result.withdrawn
    assert_predicate missing.reload, :withdrawn?
    assert_predicate @source.spending_awards.find_by!(external_key: "CA-3-A020449003"), :published?
  end

  test "marks the ingestion failed for malformed XML" do
    assert_raises(Nokogiri::XML::SyntaxError) do
      @ingestion.spending_loader.load(body: "<projects>")
    end

    assert_equal "failed", @ingestion.reload.status
    assert @ingestion.error_message.present?
  end

  private

  def create_ingestion(checksum)
    @source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/projects.xml",
      checksum: checksum,
      status: :pending
    )
  end
end
