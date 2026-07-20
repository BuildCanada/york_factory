require "test_helper"

class Api::V1::Kpis::SeriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(4)

    unit = Warehouse::Unit.find_or_create_by!(symbol: "intl_$") do |u|
      u.kind = "absolute"
      u.base_unit = "dollars"
    end
    @measure = Warehouse::Measure.create!(
      organization_id: nil,
      slug: "gdp-series-test-#{suffix}",
      canonical_name: "GDP series test",
      unit: unit,
      aggregation_type: "non_aggregable",
      frequency: "annual",
      category: "economy"
    )

    @canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    @usa = Warehouse::Jurisdiction.find_or_create_by!(code: "USA") do |j|
      j.name = "United States"
      j.slug = "united-states"
      j.level = "national"
      j.fiscal_year_start_month = 1
      j.default_currency = "USD"
    end

    @source = Warehouse::Source.create!(
      name: "econ_worldbank_series_test_#{suffix}",
      url: "https://api.worldbank.org/v2/test",
      format: "worldbank_json",
      last_fetched_at: Time.current,
      license: "CC BY 4.0",
      attribution: "World Bank Open Data (data.worldbank.org), CC BY 4.0"
    )
    raw_ingestion = @source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/#{suffix}.json",
      checksum: SecureRandom.hex(32),
      status: :complete
    )
    @document = Warehouse::KpiDocument.create!(
      doc_url: "https://api.worldbank.org/v2/test#ingestion-#{suffix}",
      jurisdiction_id: @canada.id,
      raw_ingestion_id: raw_ingestion.id,
      fiscal_year: 2026,
      published_at: Date.current
    )

    { @canada => { 2020 => 45_000.0, 2021 => 46_000.0 }, @usa => { 2020 => 63_000.0 } }.each do |jurisdiction, years|
      years.each do |year, value|
        Warehouse::ExtractedObservation.create!(
          measure_id: @measure.id,
          measurement_year: year,
          value_type: "actual",
          period_basis: "full_year",
          value_numeric: value,
          jurisdiction_id: jurisdiction.id,
          document_id: @document.id
        ).promote_to_canonical!(approved_by: "test", status: "reported", vintage_date: Date.current)
      end
    end
  end

  test "returns series grouped by jurisdiction with year-ascending points" do
    get "/api/v1/kpis/series", params: { measure: @measure.slug }

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal @measure.slug, body.dig("data", "measure", "slug")
    assert_equal "intl_$", body.dig("data", "measure", "unit", "symbol")

    series = body.dig("data", "series")
    assert_equal 2, series.size

    canada_series = series.find { |s| s.dig("jurisdiction", "code") == "CA" }
    assert_equal false, canada_series["computed"]
    assert_equal [ { "year" => 2020, "value" => 45_000.0 }, { "year" => 2021, "value" => 46_000.0 } ],
                 canada_series["points"]

    assert_equal @source.name, body.dig("meta", "source", "name")
    assert_equal "CC BY 4.0", body.dig("meta", "source", "license")
    assert_equal "World Bank Open Data (data.worldbank.org), CC BY 4.0", body.dig("meta", "source", "attribution")
    assert_equal [ 2020, 2021 ], body.dig("meta", "year_range")
  end

  test "filters by jurisdiction slugs and year bounds" do
    get "/api/v1/kpis/series", params: { measure: @measure.slug, jurisdictions: @canada.slug, from: 2021 }

    body = JSON.parse(response.body)
    series = body.dig("data", "series")

    assert_equal 1, series.size
    assert_equal "CA", series.first.dig("jurisdiction", "code")
    assert_equal [ 2021 ], series.first["points"].map { |p| p["year"] }
  end

  test "serves monthly measures as date-keyed points" do
    unit = Warehouse::Unit.find_or_create_by!(symbol: "index") do |u|
      u.kind = "ratio"
      u.base_unit = "ratio"
    end
    monthly = Warehouse::Measure.create!(
      organization_id: nil,
      slug: "cpi-series-test-#{SecureRandom.hex(4)}",
      canonical_name: "CPI series test",
      unit: unit,
      aggregation_type: "non_aggregable",
      frequency: "monthly",
      category: "economy"
    )
    { Date.new(2026, 4, 1) => 165.1, Date.new(2026, 5, 1) => 165.7 }.each do |month, value|
      Warehouse::ExtractedObservation.create!(
        measure_id: monthly.id,
        measurement_year: month.year,
        value_type: "actual",
        period_basis: "month",
        period_start: month,
        period_end: month.end_of_month,
        period_type: "month",
        value_numeric: value,
        jurisdiction_id: @canada.id,
        document_id: @document.id
      ).promote_to_canonical!(approved_by: "test", status: "reported", vintage_date: Date.current)
    end

    get "/api/v1/kpis/series", params: { measure: monthly.slug }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "monthly", body.dig("data", "measure", "frequency")

    series = body.dig("data", "series")
    assert_equal 1, series.size
    assert_equal [ { "date" => "2026-04-01", "value" => 165.1 }, { "date" => "2026-05-01", "value" => 165.7 } ],
                 series.first["points"]
    assert_equal [ 2026, 2026 ], body.dig("meta", "year_range")
  end

  test "serves quarterly measures as date-keyed points" do
    unit = Warehouse::Unit.find_or_create_by!(symbol: "$M") do |u|
      u.kind = "absolute"
      u.base_unit = "dollars"
      u.scale = 1_000_000.0
      u.currency_code = "CAD"
    end
    quarterly = Warehouse::Measure.create!(
      organization_id: nil,
      slug: "fdi-series-test-#{SecureRandom.hex(4)}",
      canonical_name: "FDI series test",
      unit: unit,
      aggregation_type: "non_aggregable",
      frequency: "quarterly",
      category: "economy"
    )
    { Date.new(2025, 10, 1) => 24_519.0, Date.new(2026, 1, 1) => 20_133.0 }.each do |quarter, value|
      Warehouse::ExtractedObservation.create!(
        measure_id: quarterly.id,
        measurement_year: quarter.year,
        value_type: "actual",
        period_basis: "quarter",
        period_start: quarter,
        period_end: quarter.end_of_quarter,
        period_type: "quarter",
        value_numeric: value,
        jurisdiction_id: @canada.id,
        document_id: @document.id
      ).promote_to_canonical!(approved_by: "test", status: "reported", vintage_date: Date.current)
    end

    get "/api/v1/kpis/series", params: { measure: quarterly.slug }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "quarterly", body.dig("data", "measure", "frequency")

    series = body.dig("data", "series")
    assert_equal 1, series.size
    assert_equal [ { "date" => "2025-10-01", "value" => 24_519.0 }, { "date" => "2026-01-01", "value" => 20_133.0 } ],
                 series.first["points"]
    assert_equal [ 2025, 2026 ], body.dig("meta", "year_range")
  end

  test "returns 404 for an unknown measure" do
    get "/api/v1/kpis/series", params: { measure: "no-such-measure" }

    assert_response :not_found
  end

  test "serves conditional requests with ETag and cache headers" do
    get "/api/v1/kpis/series", params: { measure: @measure.slug }
    assert_response :success
    assert_equal "max-age=3600, public", response.headers["Cache-Control"]
    etag = response.headers["ETag"]
    assert etag.present?

    get "/api/v1/kpis/series", params: { measure: @measure.slug }, headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end
end
