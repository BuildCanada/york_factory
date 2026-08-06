require "test_helper"

class SpendingCompatibilityTest < ActionDispatch::IntegrationTest
  setup do
    @contract = create_award(
      "spending_proactive_contracts",
      external_key: "contract-key",
      award_type: "contract",
      title: "Software support",
      description: "Open source software support",
      payer_name: "Treasury Board of Canada Secretariat",
      recipient_name: "Example Vendor",
      program_name: "Digital operations",
      fiscal_year: 2024,
      amount: 12_500,
      province_code: "ON",
      country_code: "CA",
      metadata: {
        "reference_number" => "C-1",
        "procurement_id" => "P-1",
        "trade_agreement" => "WTO-AGP"
      }
    )
    @cihr = create_award(
      "spending_cihr_awards",
      external_key: "cihr-1",
      title: "Health research",
      description: "Research abstract",
      payer_name: "Canadian Institutes of Health Research",
      recipient_name: "University of Alberta",
      program_name: "Project Grant",
      fiscal_year: 2023,
      amount: 50_000,
      province_code: "AB",
      country_code: "CA",
      metadata: { "competition_date" => "202309", "keywords" => "health; research" }
    )
    @nserc = create_award(
      "spending_nserc_awards",
      external_key: "nserc-1",
      title: "Northern lakes",
      description: "Lake research summary",
      payer_name: "Natural Sciences and Engineering Research Council of Canada",
      recipient_name: "Ada Researcher",
      program_name: "Discovery Grants",
      fiscal_year: 2022,
      amount: 24_000,
      province_code: "QC",
      metadata: {
        "recipient_organization" => "Université Example",
        "application_id" => "APP-1",
        "department" => "Biology",
        "selection_committee" => "Ecology committee",
        "research_subject" => "Fresh water"
      }
    )
    @sshrc = create_award(
      "spending_sshrc_awards",
      external_key: "sshrc-1",
      title: "Community history",
      payer_name: "Social Sciences and Humanities Research Council of Canada",
      recipient_name: "Grace Scholar",
      program_name: "Insight Grant",
      fiscal_year: 2021,
      amount: 18_000,
      metadata: { "applicant" => "Grace Scholar", "organization" => "Example College", "keywords" => "history" }
    )
    @global = create_award(
      "spending_global_affairs_projects",
      external_key: "CA-3-1",
      award_type: "contribution",
      title: "Water access",
      description: "Improve access to clean water",
      payer_name: "Global Affairs Canada",
      recipient_name: "Aid Partner",
      program_name: "Global Issues",
      fiscal_year: 2020,
      amount: 1_000_000,
      country_code: "KE",
      metadata: {
        "status" => "Operational",
        "end_date" => "2025-03-31",
        "expected_results" => "More clean water",
        "sectors" => [ "Water 100%" ],
        "policy_markers" => [ "Gender equality" ],
        "regions" => [ "Africa" ]
      }
    )
    @transfer = create_award(
      "spending_transfer_payments",
      external_key: "transfer-1",
      award_type: "transfer_payment",
      title: "Industry support",
      payer_name: "Department of Industry",
      recipient_name: "Example Association",
      program_name: "Industry grants",
      fiscal_year: 2019,
      amount: 75_000,
      province_code: "BC",
      country_code: "CA",
      metadata: { "MINC" => "12", "MINE" => "Industry", "CTY_EN_NM" => "Vancouver" }
    )
  end

  test "serves the existing Typesense multi-search contract" do
    post "/multi_search", params: {
      searches: [ {
        collection: "records",
        q: "software",
        query_by: "recipient,program,description",
        filter_by: "payer:=[`Treasury Board of Canada Secretariat`]",
        facet_by: "payer,fiscal_year,province,award_type",
        page: 1,
        per_page: 25
      } ]
    }, as: :json

    assert_response :success
    result = response.parsed_body.fetch("results").sole
    assert_equal 1, result.fetch("found")
    assert_equal 25, result.dig("request_params", "per_page")
    document = result.fetch("hits").sole.fetch("document")
    assert_equal @contract.search_id, document.fetch("id")
    assert_equal "contract-key", document.fetch("key")
    assert_equal "canada-spends.db/contracts-over-10k", document.fetch("type")
    assert_equal "2024-2025", document.fetch("fiscal_year")
    assert_equal 12_500.0, document.fetch("amount")
    assert_equal "Ontario", document.fetch("province")
    assert_equal "Canada", document.fetch("country")
    assert_equal %w[award_type fiscal_year payer province], result.fetch("facet_counts").pluck("field_name").sort
    province = result.fetch("facet_counts").find { |facet| facet.fetch("field_name") == "province" }
    assert_equal "Ontario", province.fetch("counts").sole.fetch("value")
  end

  test "accepts the text/plain JSON emitted by the Typesense JavaScript client" do
    payload = {
      searches: [ { collection: "records", q: "software", page: 1, per_page: 25 } ]
    }.to_json

    post "/multi_search", params: payload, headers: { "CONTENT_TYPE" => "text/plain" }

    assert_response :success
    assert_equal @contract.search_id,
      response.parsed_body.fetch("results").sole.fetch("hits").sole.dig("document", "id")
  end

  test "serves facet typeahead through multi-search" do
    post "/multi_search", params: {
      searches: [ {
        collection: "records", q: "*", facet_by: "payer",
        facet_query: "payer:treasury", per_page: 0, max_facet_values: 30
      } ]
    }, as: :json

    assert_response :success
    result = response.parsed_body.fetch("results").sole
    assert_empty result.fetch("hits")
    assert_equal "Treasury Board of Canada Secretariat",
      result.fetch("facet_counts").sole.fetch("counts").sole.fetch("value")
  end

  test "serves single-search and normalized APIs without authentication" do
    get "/collections/records/documents/search", params: { q: "health", per_page: 10 }
    assert_response :success
    assert_equal @cihr.search_id, response.parsed_body.fetch("hits").sole.dig("document", "id")

    get "/api/v1/spending/search", params: { q: "health", per_page: 10 }
    assert_response :success
    assert_equal 1, response.parsed_body.dig("meta", "total")

    get "/api/v1/spending/databases/cihr_grants/awards/cihr-1"
    assert_response :success
    assert_equal "cihr-1", response.parsed_body.dig("data", "key")
    assert_equal "Open Government Licence", response.parsed_body.dig("data", "source", "license")
  end

  test "serves Datasette-compatible contract details" do
    get "/canada-spends/contracts-over-10k/contract-key.json", params: { _shape: "array" }

    assert_response :success
    contract = response.parsed_body.sole
    assert_equal "C-1", contract.fetch("reference_number")
    assert_equal "Example Vendor", contract.fetch("vendor_name")
    assert_equal "WTO-AGP", contract.fetch("trade_agreement")
    assert_equal 12_500.0, contract.fetch("contract_value")
  end

  test "serves null-safe CIHR details expected by CanadaSpends" do
    get "/canada-spends/cihr_grants/cihr-1.json", params: { _shape: "array" }

    assert_response :success
    grant = response.parsed_body.sole
    assert_equal "202309", grant.fetch("competition_year")
    assert_equal "health; research", grant.fetch("keywords")
    assert_equal "University of Alberta", grant.fetch("institution")
    assert_equal "cihr-1", grant.fetch("external_id")
  end

  test "serves every other legacy detail schema expected by CanadaSpends" do
    {
      "nserc_grants/nserc-1" => {
        "institution" => "Université Example", "application_id" => "APP-1",
        "selection_committee" => "Ecology committee"
      },
      "sshrc_grants/sshrc-1" => {
        "applicant" => "Grace Scholar", "organization" => "Example College",
        "keywords" => "history"
      },
      "global_affairs_grants/CA-3-1" => {
        "projectNumber" => "CA-3-1", "expectedResults" => "More clean water",
        "DACSectors" => [ "Water 100%" ].to_json
      },
      "transfers/transfer-1" => {
        "MINC" => "12", "RCPNT_NML_EN_DESC" => "Example Association",
        "AGRG_PYMT_AMT" => 75_000.0
      }
    }.each do |path, expected|
      get "/canada-spends/#{path}.json", params: { _shape: "array" }
      assert_response :success, path
      expected.each { |field, value| assert_equal value, response.parsed_body.sole.fetch(field), "#{path}: #{field}" }
    end
  end

  test "returns not found for unknown databases and withdrawn awards" do
    get "/canada-spends/unknown/contract-key.json", params: { _shape: "array" }
    assert_response :not_found
    assert_equal [], response.parsed_body

    @contract.update!(state: "withdrawn")
    get "/canada-spends/contracts-over-10k/contract-key.json", params: { _shape: "array" }
    assert_response :not_found
  end

  private

  def create_award(source_name, attributes)
    source = Warehouse::Source.create!(
      name: source_name,
      url: "https://example.test/#{source_name}",
      format: "csv",
      attribution: "Government of Canada",
      license: "Open Government Licence"
    )
    now = Time.current
    Warehouse::SpendingAward.create!({
      source:,
      external_key: SecureRandom.hex(8),
      award_type: "grant",
      title: "Award",
      occurred_at: Time.zone.parse("2024-04-01"),
      currency: "CAD",
      first_seen_at: now,
      last_seen_at: now
    }.merge(attributes))
  end
end
