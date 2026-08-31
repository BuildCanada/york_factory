require "test_helper"

class Api::V1::Warehouse::MunicipalFinancialStatementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @release = Warehouse::InstitutionRelease.create!(
      version: "2026-08-28", effective_on: Date.new(2026, 8, 28), schema_version: "1.0",
      published_at: Time.utc(2026, 8, 28), geography_vintage: 2021, attribution: "Test"
    )
    @source = Warehouse::InstitutionSource.create!(
      institution_release: @release, canonical_id: "ca/sources/api-test",
      publisher_name: "Test", title_en: "Test", url: "https://example.test/source",
      retrieved_at: @release.published_at, languages: [ "en" ]
    )
    @institution = Warehouse::Institution.create!(
      institution_release: @release, institution_source: @source, canonical_id: "ca/on/example-town",
      name_en: "Example Town", institution_type: "government", government_level: "municipal",
      status: "active", legal_form: "town", website_url: "https://example.test"
    )
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution: @institution, institution_source: @source,
      canonical_id: "ca/on/example-town/documents/financial-statements/2025/general",
      document_type: "financial-statements", document_variant: "general",
      source_page_url: "https://example.test/reports"
    )
    asset = Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: document, content_sha256: "f" * 64,
      asset_role: "final", preferred: true, download_url: "https://example.test/statement.pdf",
      retrieved_at: @release.published_at, archive_path: "sha256/ff/#{'f' * 64}.pdf",
      mime_type: "application/pdf", byte_size: 100, rights_status: "metadata_only"
    )
    @extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: @institution.canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31),
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: "extracted", check_results: verification_checks
    )
    @extraction.financial_statement_facts.create!(
      concept: "total_revenue", value: 12_345_678, raw_text: "12,345,678",
      raw_label: "Total revenue", scale: 1, statement: "operations", source_page: 8,
      column_year: "2025", extraction_confidence: 0.98
    )
    @extraction.financial_statement_facts.create!(
      concept: "total_expenses", value: 10_000_000, raw_text: "10,000,000",
      raw_label: "Total expenses", scale: 1, statement: "operations", source_page: 8,
      column_year: "2025", extraction_confidence: 0.98
    )
    @extraction.financial_statement_line_items.create!(
      flow: "revenue", category: "Taxes", label: "Property taxes", value: 12_345_678,
      raw_text: "12,345,678", scale: 1, source_page: 20, column_year: "2025",
      position: 0, extraction_confidence: 0.98
    )
    @extraction.financial_statement_line_items.create!(
      flow: "expense", category: "Transportation", label: "Roads", value: 10_000_000,
      raw_text: "10,000,000", scale: 1, source_page: 21, column_year: "2025",
      position: 0, extraction_confidence: 0.98
    )
    geography = @release.institution_geography_snapshots.create!(
      canonical_id: "ca/geography/csd-2021/3510001", code_system: "csd_2021",
      geo_uid: "3510001", boundary_type: "csd", classification_type: "T",
      authority_status: "verified", name_en: "Example Town", province_code: "35",
      census_year: 2021, population: 50_000, area_sq_km: 100
    )
    @release.institution_geographies.create!(
      institution: @institution, institution_geography_snapshot: geography,
      role: "governs", match_method: "authoritative_crosswalk", confidence: 1
    )
    Warehouse::CensusProfile.create!(
      census_year: 2021, geo_level: "csd", geo_uid: "3510001", population: 60_000,
      source_url: "https://example.test/census", source_sha256: "c" * 64,
      retrieved_at: Time.utc(2026, 8, 29)
    )
    @extraction.approve!(reviewer: "reviewer", notes: "independently verified")
  end

  test "index lists municipalities and their approved years" do
    get api_v1_warehouse_municipal_financial_statements_url

    assert_response :success
    payload = JSON.parse(response.body)
    municipality = payload.fetch("data").find { |row| row["canonical_id"] == @institution.canonical_id }
    assert_equal "Example Town", municipality.fetch("name")
    assert_equal "on", municipality.fetch("province")
    assert_equal [ 2025 ], municipality.fetch("available_years")
    assert_equal "2025-12-31", municipality.fetch("available_periods").sole.fetch("fiscal_year_end")
    assert_equal 1, payload.dig("meta", "page")
    assert_equal 1, payload.dig("meta", "total_pages")
  end

  test "index paginates municipalities in SQL while preserving archive-wide counts" do
    create_approved_municipality("ca/on/zeta-town", "Zeta Town", "a" * 64)

    get api_v1_warehouse_municipal_financial_statements_url, params: { page: 1, per_page: 1 }
    first_page = JSON.parse(response.body)
    get api_v1_warehouse_municipal_financial_statements_url, params: { page: 2, per_page: 1 }
    second_page = JSON.parse(response.body)

    assert_equal 1, first_page.fetch("data").length
    assert_equal 1, second_page.fetch("data").length
    refute_equal first_page.dig("data", 0, "canonical_id"), second_page.dig("data", 0, "canonical_id")
    assert_equal 2, first_page.dig("meta", "municipality_count")
    assert_equal 2, first_page.dig("meta", "statement_count")
    assert_equal 2, first_page.dig("meta", "total_pages")
  end

  test "normalizes Ontario and Alberta city legal forms for display" do
    controller = Api::V1::Warehouse::MunicipalFinancialStatementsController.new

    assert_equal "Toronto", controller.send(:display_name, "Toronto, City of", "on")
    assert_equal "Calgary", controller.send(:display_name, "City of Calgary", "ab")
    assert_equal "City of Vancouver", controller.send(:display_name, "City of Vancouver", "bc")
  end

  test "year-scoped show preserves every approved available year" do
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution: @institution, institution_source: @source,
      canonical_id: "ca/on/example-town/documents/financial-statements/2024/general",
      document_type: "financial-statements", document_variant: "general"
    )
    asset = Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: document, content_sha256: "d" * 64,
      asset_role: "final", preferred: true, download_url: "https://example.test/statement-2024.pdf",
      retrieved_at: @release.published_at, archive_path: "sha256/dd/#{'d' * 64}.pdf",
      mime_type: "application/pdf", byte_size: 100, rights_status: "metadata_only"
    )
    older = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: @institution.canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: asset.content_sha256,
      fiscal_year_end: Date.new(2024, 12, 31),
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: "extracted", check_results: verification_checks
    )
    older.approve!(reviewer: "reviewer")

    get "/api/v1/warehouse/municipal_financial_statements/on/example-town/2025"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ 2025, 2024 ], payload.fetch("available_years")
    assert_equal [ 2025 ], payload.fetch("statements").pluck("fiscal_year")
  end

  test "approved headline-only years are not published" do
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution: @institution, institution_source: @source,
      canonical_id: "ca/on/example-town/documents/financial-statements/2024/general",
      document_type: "financial-statements", document_variant: "general"
    )
    asset = Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: document, content_sha256: "d" * 64,
      asset_role: "final", preferred: true, download_url: "https://example.test/statement-2024.pdf",
      retrieved_at: @release.published_at, archive_path: "sha256/dd/#{'d' * 64}.pdf",
      mime_type: "application/pdf", byte_size: 100, rights_status: "metadata_only"
    )
    headline = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: @institution.canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: asset.content_sha256,
      fiscal_year_end: Date.new(2024, 12, 31),
      extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
      status: "extracted", check_results: verification_checks
    )
    headline.approve!(reviewer: "reviewer")

    get "/api/v1/warehouse/municipal_financial_statements/on/example-town/2024"
    assert_response :not_found

    get api_v1_warehouse_municipal_financial_statements_url
    assert_equal [ 2025 ], JSON.parse(response.body).fetch("data").sole.fetch("available_years")
  end

  test "show returns normalized facts and source provenance" do
    get "/api/v1/warehouse/municipal_financial_statements/on/example-town/2025"

    assert_response :success
    statement = JSON.parse(response.body).fetch("statements").sole
    assert_equal "https://example.test/statement.pdf", statement.dig("source", "download_url")
    fact = statement.fetch("facts").find { |row| row["concept"] == "total_revenue" }
    assert_equal "total_revenue", fact.fetch("concept")
    assert_equal 12_345_678.0, fact.fetch("value")
    assert_equal 8, fact.fetch("source_page")
    assert_equal 60_000, JSON.parse(response.body).dig("context", "population")
    assert_equal 166.67, statement.dig("per_capita", "total_expenses")
    assert_equal "Taxes", statement.dig("sankey", "revenue_data", "children", 0, "name")
    assert_equal "Property taxes", statement.fetch("line_items").find { _1["flow"] == "revenue" }.fetch("label")
    assert_equal "approved", statement.dig("verification", "status")
    assert_equal "reviewer", statement.dig("verification", "reviewed_by")
    assert statement.dig("verification", "reviewed_at").present?
    assert_equal "independently verified", statement.dig("verification", "review_notes")
    assert_equal({ "total" => 2, "pass" => 1, "skip" => 1, "fail" => 0 }, statement.dig("verification", "summary"))
    assert_equal verification_checks.map { _1.stringify_keys }, statement.dig("verification", "checks")
  end

  test "unknown verification statuses count as failures" do
    @extraction.update_column(:check_results, verification_checks + [
      { id: "future_check", status: "unknown", detail: "new status" }
    ])

    get "/api/v1/warehouse/municipal_financial_statements/on/example-town/2025"

    assert_equal 1, JSON.parse(response.body).dig("statements", 0, "verification", "summary", "fail")
  end

  test "does not publish a Sankey that would contradict headline totals" do
    @extraction.financial_statement_line_items.create!(
      flow: "revenue", category: "Adjustments", label: "Consolidation adjustment", value: -20_000,
      raw_text: "(20,000)", scale: 1, source_page: 20, column_year: "2025",
      position: 1, extraction_confidence: 0.98
    )

    get "/api/v1/warehouse/municipal_financial_statements/on/example-town/2025"

    statement = JSON.parse(response.body).fetch("statements").sole
    assert_nil statement.fetch("sankey")
    assert_equal(-20_000.0,
      statement.fetch("line_items").find { _1["label"] == "Consolidation adjustment" }.fetch("value"))
  end

  test "repositions signed adjustments into a nonnegative Sankey without changing reported rows" do
    @extraction.financial_statement_line_items.find_by!(flow: "revenue").update_column(:value, 12_345_778)
    @extraction.financial_statement_line_items.find_by!(flow: "expense").update_column(:value, 10_000_040)
    @extraction.financial_statement_line_items.create!(
      flow: "revenue", category: "Adjustments", label: "Loss on disposal", value: -100,
      raw_text: "(100)", scale: 1, source_page: 20, column_year: "2025",
      position: 1, extraction_confidence: 0.98
    )
    @extraction.financial_statement_line_items.create!(
      flow: "expense", category: "Adjustments", label: "Expense recovery", value: -40,
      raw_text: "(40)", scale: 1, source_page: 21, column_year: "2025",
      position: 1, extraction_confidence: 0.98
    )
    @extraction.financial_statement_line_items.create!(
      flow: "revenue", category: "Adjustments", label: "Nil adjustment", value: 0,
      raw_text: "-", scale: 1, source_page: 20, column_year: "2025",
      position: 2, extraction_confidence: 0.98
    )

    get "/api/v1/warehouse/municipal_financial_statements/on/example-town/2025"

    statement = JSON.parse(response.body).fetch("statements").sole
    sankey = statement.fetch("sankey")
    revenue_leaves = sankey.dig("revenue_data", "children").flat_map { _1.fetch("children") }
    spending_leaves = sankey.dig("spending_data", "children").flat_map { _1.fetch("children") }
    assert_equal "Inflows", sankey.dig("revenue_data", "name")
    assert_equal "Outflows", sankey.dig("spending_data", "name")
    assert_equal 12_345_678.0, sankey.fetch("revenue")
    assert_equal 10_000_000.0, sankey.fetch("spending")
    assert_equal 12_345_818.0, sankey.fetch("total")
    assert_equal 2_345_678.0, revenue_leaves.sum { _1.fetch("amount") } -
      spending_leaves.sum { _1.fetch("amount") }
    assert spending_leaves.any? { _1.fetch("id").start_with?("expense-revenue-") && _1.fetch("name") == "Loss on disposal" }
    assert revenue_leaves.any? { _1.fetch("id").start_with?("revenue-expense-") && _1.fetch("name") == "Expense recovery" }
    refute (revenue_leaves + spending_leaves).any? { _1.fetch("name") == "Nil adjustment" }
    assert_equal(-100.0, statement.fetch("line_items").find { _1["label"] == "Loss on disposal" }.fetch("value"))
    assert_equal(-40.0, statement.fetch("line_items").find { _1["label"] == "Expense recovery" }.fetch("value"))
    assert_equal 0.0, statement.fetch("line_items").find { _1["label"] == "Nil adjustment" }.fetch("value")
  end

  test "publishes a positive Sankey using an independently verified adjustment basis" do
    @extraction.financial_statement_line_items.create!(
      flow: "revenue", category: "Contributions", label: "Capital contributions", value: 100,
      raw_text: "100", scale: 1, source_page: 20, column_year: "2025",
      position: 1, extraction_confidence: 0.98
    )
    @extraction.update_column(:check_results, verification_checks + [
      { id: "line_sum:revenue", status: "pass", detail: "verified adjustment basis" }
    ])

    get "/api/v1/warehouse/municipal_financial_statements/on/example-town/2025"

    statement = JSON.parse(response.body).fetch("statements").sole
    assert_equal 12_345_778.0, statement.dig("sankey", "revenue")
    assert_equal "Capital contributions",
      statement.dig("sankey", "revenue_data", "children", 1, "children", 0, "name")
  end

  test "newest release wins when a fiscal year has multiple approved extractions" do
    newer_release = Warehouse::InstitutionRelease.create!(
      version: "2026-08-29", effective_on: Date.new(2026, 8, 29), schema_version: "1.0",
      published_at: Time.utc(2026, 8, 29), geography_vintage: 2021, attribution: "Test"
    )
    source = Warehouse::InstitutionSource.create!(
      institution_release: newer_release, canonical_id: "ca/sources/api-test",
      publisher_name: "Test", title_en: "Test", url: "https://example.test/source",
      retrieved_at: newer_release.published_at, languages: [ "en" ]
    )
    institution = Warehouse::Institution.create!(
      institution_release: newer_release, institution_source: source,
      canonical_id: @institution.canonical_id, name_en: "Example Town Updated",
      institution_type: "government", government_level: "municipal", status: "active"
    )
    document = Warehouse::InstitutionDocument.create!(
      institution_release: newer_release, institution:, institution_source: source,
      canonical_id: "ca/on/example-town/documents/financial-statements/2025/general",
      document_type: "financial-statements", document_variant: "general"
    )
    asset = Warehouse::InstitutionDocumentAsset.create!(
      institution_release: newer_release, institution_document: document, content_sha256: "e" * 64,
      asset_role: "final", preferred: true, download_url: "https://example.test/newer.pdf",
      retrieved_at: newer_release.published_at, archive_path: "sha256/ee/#{'e' * 64}.pdf",
      mime_type: "application/pdf", byte_size: 100, rights_status: "metadata_only"
    )
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: newer_release, institution_canonical_id: institution.canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31),
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: "extracted", check_results: verification_checks
    )
    extraction.financial_statement_facts.create!(
      concept: "total_revenue", value: 99_000_000, raw_text: "99,000,000",
      raw_label: "Total revenue", scale: 1, statement: "operations", source_page: 9,
      column_year: "2025", extraction_confidence: 0.99
    )
    extraction.approve!(reviewer: "reviewer")

    get "/api/v1/warehouse/municipal_financial_statements/ontario/example-town/2025"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "Example Town Updated", payload.fetch("name")
    assert_equal 99_000_000.0, payload.dig("statements", 0, "facts", 0, "value")
    assert_equal "https://example.test/newer.pdf", payload.dig("statements", 0, "source", "download_url")
  end

  test "show does not expose unapproved extractions" do
    @extraction.update!(status: "rejected")

    get "/api/v1/warehouse/municipal_financial_statements/on/example-town/2025"

    assert_response :not_found
  end

  test "nested regional-government ids use stable route slugs" do
    institution = Warehouse::Institution.create!(
      institution_release: @release, institution_source: @source,
      canonical_id: "ca/bc/regional/example", name_en: "Example Regional District",
      institution_type: "government", government_level: "regional", status: "active"
    )
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution:, institution_source: @source,
      canonical_id: "ca/bc/regional/example/documents/financial-statements/2025/general",
      document_type: "financial-statements", document_variant: "general"
    )
    asset = Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: document, content_sha256: "b" * 64,
      asset_role: "final", preferred: true, download_url: "https://example.test/regional.pdf",
      retrieved_at: @release.published_at, archive_path: "sha256/bb/#{'b' * 64}.pdf",
      mime_type: "application/pdf", byte_size: 100, rights_status: "metadata_only"
    )
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: institution.canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31),
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: "extracted", check_results: verification_checks
    )
    extraction.approve!(reviewer: "reviewer")

    get "/api/v1/warehouse/municipal_financial_statements/bc/regional--example/2025"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "regional--example", payload.fetch("slug")
    assert_equal "ca/bc/regional/example", payload.fetch("canonical_id")
  end

  private

  def create_approved_municipality(canonical_id, name, sha)
    institution = Warehouse::Institution.create!(
      institution_release: @release, institution_source: @source, canonical_id:, name_en: name,
      institution_type: "government", government_level: "municipal", status: "active"
    )
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution:, institution_source: @source,
      canonical_id: "#{canonical_id}/documents/financial-statements/2025/general",
      document_type: "financial-statements", document_variant: "general"
    )
    asset = Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: document, content_sha256: sha,
      asset_role: "final", preferred: true, download_url: "https://example.test/zeta.pdf",
      retrieved_at: @release.published_at, archive_path: "sha256/#{sha.first(2)}/#{sha}.pdf",
      mime_type: "application/pdf", byte_size: 100, rights_status: "metadata_only"
    )
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31),
      extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      status: "extracted", check_results: verification_checks
    )
    extraction.approve!(reviewer: "reviewer")
  end

  def verification_checks
    [
      { id: "source_identity", status: "pass", detail: "source hash matches" },
      { id: "population_context", status: "skip", detail: "not required for approval" }
    ]
  end
end
