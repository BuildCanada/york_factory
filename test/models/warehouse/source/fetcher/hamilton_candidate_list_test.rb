require "test_helper"

class Warehouse::Source::Fetcher::HamiltonCandidateListTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:status, :body)

  class FakeHttp
    attr_reader :requested_urls

    def initialize(response)
      @response = response
      @requested_urls = []
    end

    def get(url)
      @requested_urls << url
      @response
    end
  end

  URL = "https://www.hamilton.ca/city-council/municipal-election/candidates-third-party-advertisers/candidates".freeze

  # Mirrors the page: three tab containers, councillor and trustee tabs
  # grouping candidates into accordion items labelled by district.
  def page(mayor: nil, councillor: [], trustee: [], chrome: "<nav>1MB of page chrome</nav>")
    <<~HTML
      <html><body>#{chrome}
        <div class="tabs-content">
          #{"<div id=\"nav-mayor-content\">#{mayor}</div>" if mayor}
          #{"<div id=\"nav-councillor-content\">#{councillor.join}</div>" if councillor.any?}
          #{"<div id=\"nav-trustee-content\">#{trustee.join}</div>" if trustee.any?}
        </div>
      </body></html>
    HTML
  end

  def accordion(label:, table: nil)
    <<~HTML
      <div class="accordion-item">
        <button class="accordion-item--toggle" type="button">
          #{label}
        </button>
        <div class="accordion-item--content">#{table}</div>
      </div>
    HTML
  end

  # The page's normal table: a <thead> of <th>.
  def table(rows)
    head = "<thead><tr><th>Name</th><th>Address</th><th>Phone</th><th>Email</th></tr></thead>"
    "<table>#{head}<tbody>#{rows.join}</tbody></table>"
  end

  # At least one real table has no <thead> and uses <td> for its header row.
  def headerless_table(rows)
    "<table><tbody><tr><td>Name</td><td>Address</td><td>Phone</td><td>Email</td></tr>#{rows.join}</tbody></table>"
  end

  def row(name:, address: "-", phone: "-", email: :obfuscated)
    cell = case email
    when :obfuscated
      '<a href="/cdn-cgi/l/email-protection" class="__cf_email__" data-cfemail="ef8c8699868c">[email&#160;protected]</a>'
    when nil then "-"
    else "<a href=\"mailto:#{email}\">#{email}</a>"
    end
    "<tr><td>#{name}</td><td>#{address}</td><td>#{phone}</td><td>#{cell}</td></tr>"
  end

  def fetch(html)
    http = FakeHttp.new(FakeResponse.new(200, html))
    JSON.parse(Warehouse::Source::Fetcher::HamiltonCandidateList.new(URL, year: "2026", http: http).call)
  end

  test "parses the three tabs into a canonical body" do
    html = page(
      mayor: table([ row(name: "Cooper, Rob", phone: "289-768-2964"), row(name: "Austin, Sasha") ]),
      councillor: [ accordion(label: "Ward 1", table: table([ row(name: "Wilson, Maureen", address: "14 Amelia St., Hamilton, ON L8P 2V4") ])) ],
      trustee: [ accordion(label: "Wards 5 &amp; 10 - English Public", table: table([ row(name: "Floyd, Seth") ])) ]
    )

    parsed = fetch(html)

    assert_equal %w[year offices], parsed.keys
    assert_equal "2026", parsed["year"]
    assert_equal %w[mayor councillor trustee], parsed["offices"].map { |o| o["section"] }
    assert_equal [ nil, "Ward 1", "Wards 5 & 10 - English Public" ], parsed["offices"].map { |o| o["label"] }

    # Sorted by name, so a reordered table isn't a data change.
    mayor = parsed["offices"].first
    assert_equal [ "Austin, Sasha", "Cooper, Rob" ], mayor["candidates"].map { |c| c["name"] }
    assert_equal "289-768-2964", mayor["candidates"].last["phone"]
    assert_nil mayor["candidates"].first["phone"]

    # Addresses are candidates' home addresses and are never collected.
    assert_equal %w[name phone email], parsed["offices"][1]["candidates"].sole.keys
  end

  test "Cloudflare-obfuscated emails are left alone" do
    html = page(mayor: table([ row(name: "Butt, Ejaz") ]))

    assert_nil fetch(html)["offices"].sole["candidates"].sole["email"]
  end

  test "a plainly published email is kept" do
    html = page(mayor: table([ row(name: "Butt, Ejaz", email: "ejaz@example.ca") ]))

    assert_equal "ejaz@example.ca", fetch(html)["offices"].sole["candidates"].sole["email"]
  end

  test "a table whose header row is plain cells is parsed without leaking a candidate named Name" do
    html = page(mayor: headerless_table([ row(name: "Floyd, Seth", phone: "905-555-0100") ]))

    candidates = fetch(html)["offices"].sole["candidates"]

    assert_equal [ "Floyd, Seth" ], candidates.map { |c| c["name"] }
    assert_equal "905-555-0100", candidates.sole["phone"]
  end

  test "columns are read by header name, not position" do
    html = page(mayor: <<~HTML)
      <table><thead><tr><th>Phone</th><th>Name</th></tr></thead>
      <tbody><tr><td>905-555-0100</td><td>Floyd, Seth</td></tr></tbody></table>
    HTML

    candidate = fetch(html)["offices"].sole["candidates"].sole

    assert_equal "Floyd, Seth", candidate["name"]
    assert_equal "905-555-0100", candidate["phone"]
  end

  test "an accordion district with no table reads as an empty race" do
    html = page(trustee: [ accordion(label: "Ward 1 - English Public") ])

    office = fetch(html)["offices"].sole

    assert_equal "Ward 1 - English Public", office["label"]
    assert_equal [], office["candidates"]
  end

  test "the page's blank marker reads as nil" do
    html = page(mayor: table([ row(name: "Austin, Sasha", phone: "-", email: nil) ]))

    candidate = fetch(html)["offices"].sole["candidates"].sole

    assert_nil candidate["phone"]
    assert_nil candidate["email"]
  end

  test "volatile page chrome and a reordered table produce an identical body" do
    rows = [ row(name: "Austin, Sasha"), row(name: "Cooper, Rob") ]
    first = page(mayor: table(rows), chrome: "<nav>build 0xAAA</nav>")
    second = page(mayor: table(rows.reverse), chrome: "<nav>build 0xBBB</nav>")

    build = ->(html) do
      http = FakeHttp.new(FakeResponse.new(200, html))
      Warehouse::Source::Fetcher::HamiltonCandidateList.new(URL, year: "2026", http: http).call
    end

    assert_equal build.call(first), build.call(second)
  end

  test "a page with none of the tab containers raises" do
    error = assert_raises(RuntimeError) { fetch("<html><body><p>Redesigned</p></body></html>") }

    assert_match(/#nav-mayor-content/, error.message)
  end

  test "a non-200 response raises" do
    http = FakeHttp.new(FakeResponse.new(503, ""))

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::HamiltonCandidateList.new(URL, year: "2026", http: http).call
    end
    assert_match(/HTTP 503/, error.message)
  end

  test "requires a year" do
    assert_raises(ArgumentError) { Warehouse::Source::Fetcher::HamiltonCandidateList.new(URL, year: nil) }
  end
end
