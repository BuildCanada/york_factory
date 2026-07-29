require "test_helper"

class Warehouse::Source::Fetcher::BramptonCandidateListTest < ActiveSupport::TestCase
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

  URL = "https://www.brampton.ca/EN/City-Hall/Election/Candidates/Pages/candidateListing.aspx".freeze

  # Mirrors the page's markup: office groupings carry the office code and the
  # wards they cover, each candidate is an accordion item with a data sort key
  # and a packed filing date.
  def grouping(code:, heading:, wards:, candidates: [])
    <<~HTML
      <div class="row row-cols-1 office-grouping" data-wards="[#{wards.map { |w| "&quot;ward-#{w}&quot;" }.join(", ")}]" data-office="#{code}">
        <div class="col office-heading"><h3>#{heading}</h3></div>
        <div class="col accordion office-candidate-listing">#{candidates.join}</div>
      </div>
    HTML
  end

  def candidate_item(name:, sort_key:, date: "05082026", date_text: "5/8/2026", withdrawn: false,
                     qualifying_address: "-", cell_phone: "-", campaign_address: "-", campaign_phone: "-",
                     socials: [])
    <<~HTML
      <div class="accordion-item candidate-details#{" candidate-withdrawn" if withdrawn}" data-date="#{date}" data-name="#{sort_key}">
        <h3 class="accordion-header"><button class="accordion-button collapsed row" type="button">
          <div class="col-8 candidate-name">#{name}#{"<span> (Withdrawn)</span>" if withdrawn}</div>
          <div class="col-12 col-md-3 filing-date d-none"><span>Filing Date: </span>#{date_text}</div>
          #{"<div class=\"sr-only\"><span>This candidate has withdrawn from this year's municipal election.</span></div>" if withdrawn}
        </button></h3>
        <div class="accordion-collapse collapse"><div class="accordion-body overflow-hidden p-0">
          <div class="row candidate-information">
            <div class="box-qualify-info col-12">
              <div><span>Qualifying Address: </span>#{qualifying_address}</div>
              <div><span>Cell Phone: </span>#{cell_phone}</div>
            </div>
            <div class="box-campaign-info col-12">
              <div><span>Campaign Address: </span>#{campaign_address}</div>
              <div><span>Campaign Phone: </span>#{campaign_phone}</div>
            </div>
            <div class="box-social-info col-12">#{socials.join}</div>
          </div>
        </div></div>
      </div>
    HTML
  end

  def social_link(icon:, text:, url: nil)
    inner = "<i class=\"#{icon} pe-3\"></i><span class=\"social-link-text\">#{text}</span>"
    body = url ? "<a href=\"#{url}\" target=\"_blank\">#{inner}</a>" : inner
    "<div class=\"candidate-social-link\">#{body}</div>"
  end

  def page(*groupings, chrome: "<input name=\"__REQUESTDIGEST\" value=\"0xVOLATILE\">")
    <<~HTML
      <html><body>#{chrome}
        <div id="candidates-module" class="row">#{groupings.join}</div>
      </body></html>
    HTML
  end

  def fetch(html)
    http = FakeHttp.new(FakeResponse.new(200, html))
    JSON.parse(Warehouse::Source::Fetcher::BramptonCandidateList.new(URL, year: "2026", http: http).call)
  end

  test "parses office groupings and candidate details into a canonical body" do
    html = page(
      grouping(code: "mayor", heading: "Mayor", wards: (1..10).to_a, candidates: [
        candidate_item(name: "Dhaliwal, Avi", sort_key: "DhaliwalAvi", date: "05042026", date_text: "5/4/2026",
          cell_phone: "416.882.1200", campaign_address: "2 Automatic Road, Brampton, Ontario",
          campaign_phone: "905.872.7000",
          socials: [
            social_link(icon: "fas fa-globe", text: "Website", url: "http://www.avidhaliwal.com"),
            social_link(icon: "fab fa-instagram", text: "Instagram", url: "http://instagram.com/avi.s.dhaliwal"),
            social_link(icon: "fas fa-envelope", text: "Email", url: "mailto:elect@avidhaliwal.com")
          ])
      ]),
      grouping(code: "cc15", heading: "Councillor, City - Wards 1, 5", wards: [ 1, 5 ])
    )

    parsed = fetch(html)

    assert_equal %w[year offices], parsed.keys
    assert_equal "2026", parsed["year"]
    assert_equal %w[mayor cc15], parsed["offices"].map { |o| o["code"] }

    mayor = parsed["offices"].first
    assert_equal "Mayor", mayor["heading"]
    assert_equal (1..10).to_a, mayor["wards"]

    avi = mayor["candidates"].sole
    assert_equal "Dhaliwal, Avi", avi["name"]
    assert_equal "05042026", avi["filing_date"]
    assert_equal "5/4/2026", avi["filing_date_text"]
    assert_equal false, avi["withdrawn"]
    assert_equal "416.882.1200", avi["cell_phone"]
    assert_equal "2 Automatic Road, Brampton, Ontario", avi["campaign_address"]
    assert_equal "elect@avidhaliwal.com", avi["email"]
    assert_equal "http://www.avidhaliwal.com", avi["website"]
    assert_equal [ { "name" => "web", "url" => "http://www.avidhaliwal.com" },
                   { "name" => "instagram", "url" => "http://instagram.com/avi.s.dhaliwal" } ], avi["socials"]

    assert_equal [ 1, 5 ], parsed["offices"].last["wards"]
    assert_equal [], parsed["offices"].last["candidates"]
  end

  test "the page's blank marker reads as nil" do
    html = page(grouping(code: "mayor", heading: "Mayor", wards: [ 1 ], candidates: [
      candidate_item(name: "Walia, Gaurav", sort_key: "WaliaGaurav",
        socials: [ social_link(icon: "fas fa-globe", text: "No site provided.") ])
    ]))

    candidate = fetch(html)["offices"].sole["candidates"].sole

    assert_nil candidate["qualifying_address"]
    assert_nil candidate["cell_phone"]
    assert_nil candidate["campaign_phone"]
    assert_nil candidate["email"]
    assert_nil candidate["website"]
    assert_equal [], candidate["socials"]
  end

  test "strips the withdrawn marker from the name and flags the candidate" do
    html = page(grouping(code: "cc34", heading: "Councillor, City - Wards 3, 4", wards: [ 3, 4 ], candidates: [
      candidate_item(name: "Campbell, Chris", sort_key: "CampbellChris", withdrawn: true)
    ]))

    candidate = fetch(html)["offices"].sole["candidates"].sole

    assert_equal "Campbell, Chris", candidate["name"]
    assert_equal true, candidate["withdrawn"]
  end

  test "drops the blank given-name marker from single-name candidates" do
    html = page(grouping(code: "mayor", heading: "Mayor", wards: [ 1 ], candidates: [
      candidate_item(name: "Gursimranjit Singh, -", sort_key: "GursimranjitSingh")
    ]))

    assert_equal "Gursimranjit Singh", fetch(html)["offices"].sole["candidates"].sole["name"]
  end

  test "normalizes brand icon classes onto the shared social vocabulary" do
    html = page(grouping(code: "mayor", heading: "Mayor", wards: [ 1 ], candidates: [
      candidate_item(name: "Somal, Sandeep", sort_key: "SomalSandeep", socials: [
        social_link(icon: "fa-brands fa-square-x-twitter", text: "X (Formerly Twitter)", url: "http://x.com/somal"),
        social_link(icon: "fab fa-tiktok", text: "TikTok", url: "http://tiktok.com/@somal")
      ])
    ]))

    assert_equal %w[twitter tiktok], fetch(html)["offices"].sole["candidates"].sole["socials"].map { |s| s["name"] }
  end

  test "volatile page chrome and a changed sort order produce an identical body" do
    candidates = [
      candidate_item(name: "Bhatt, Jagruti", sort_key: "BhattJagruti"),
      candidate_item(name: "Walia, Gaurav", sort_key: "WaliaGaurav")
    ]
    first = page(grouping(code: "mayor", heading: "Mayor", wards: [ 1 ], candidates: candidates),
      chrome: "<input name=\"__REQUESTDIGEST\" value=\"0xAAA\">")
    second = page(grouping(code: "mayor", heading: "Mayor", wards: [ 1 ], candidates: candidates.reverse),
      chrome: "<input name=\"__REQUESTDIGEST\" value=\"0xBBB\">")

    build = ->(html) do
      http = FakeHttp.new(FakeResponse.new(200, html))
      Warehouse::Source::Fetcher::BramptonCandidateList.new(URL, year: "2026", http: http).call
    end

    assert_equal build.call(first), build.call(second)
  end

  test "a page with no office groupings raises" do
    error = assert_raises(RuntimeError) { fetch(page) }

    assert_match(/no div.office-grouping blocks found/, error.message)
  end

  test "a non-200 response raises" do
    http = FakeHttp.new(FakeResponse.new(503, ""))

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::BramptonCandidateList.new(URL, year: "2026", http: http).call
    end
    assert_match(/HTTP 503/, error.message)
  end

  test "requires a year" do
    assert_raises(ArgumentError) do
      Warehouse::Source::Fetcher::BramptonCandidateList.new(URL, year: nil)
    end
  end
end
