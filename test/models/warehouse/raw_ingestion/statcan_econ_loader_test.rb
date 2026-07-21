require "test_helper"

class Warehouse::RawIngestion::StatcanEconLoaderTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(4)

    unit = Warehouse::Unit.find_or_create_by!(symbol: "ratio") do |u|
      u.kind = "ratio"
      u.base_unit = "ratio"
    end
    @measure = Warehouse::Measure.find_or_create_by!(organization_id: nil, slug: "gini-after-tax-canada") do |m|
      m.canonical_name = "Gini coefficient, adjusted after-tax income (Canada)"
      m.unit = unit
      m.aggregation_type = "non_aggregable"
      m.frequency = "annual"
    end

    [ [ "G7", "G7 (average)", "supranational" ], [ "INTL", "International", "supranational" ] ].each do |code, name, level|
      Warehouse::Jurisdiction.find_or_create_by!(code: code) do |j|
        j.name = name
        j.slug = code.downcase
        j.level = level
        j.fiscal_year_start_month = 1
        j.default_currency = "USD"
      end
    end

    source = Warehouse::Source.create!(
      name: "econ_statcan_test_#{suffix}",
      url: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=96439638&latestN=80",
      format: "statcan_json"
    )
    @raw_ingestion = source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/#{suffix}.json",
      checksum: SecureRandom.hex(32),
      status: :pending
    )
  end

  test "loads StatCan vector rows into promoted Canada observations" do
    body = JSON.generate([
      { "vectorId" => 96439638, "refPer" => "2023-01-01", "value" => 0.301 },
      { "vectorId" => 96439638, "refPer" => "2024-01-01", "value" => 0.305 },
      { "vectorId" => 96439638, "refPer" => "2022-01-01", "value" => nil },
      { "vectorId" => 12345, "refPer" => "2024-01-01", "value" => 1.0 }
    ])

    counts = @raw_ingestion.statcan_econ_loader.load(json_content: body)

    assert_equal 2, counts[:inserted]
    assert_equal 2, counts[:promoted]
    assert_equal 0, counts[:g7_rows]
    assert_equal "complete", @raw_ingestion.reload.status

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    assert Warehouse::CanonicalObservation.exists?(
      measure_id: @measure.id, jurisdiction_id: canada.id, measurement_year: 2024, value_numeric: 0.305
    )
  end

  test "loads monthly CPI vectors as one observation per month" do
    unit = Warehouse::Unit.find_or_create_by!(symbol: "index") do |u|
      u.kind = "ratio"
      u.base_unit = "ratio"
    end
    cpi = Warehouse::Measure.find_or_create_by!(organization_id: nil, slug: "cpi-all-items") do |m|
      m.canonical_name = "Consumer Price Index, all-items (2002=100)"
      m.unit = unit
      m.aggregation_type = "non_aggregable"
      m.frequency = "monthly"
    end

    body = JSON.generate([
      { "vectorId" => 41690973, "refPer" => "2026-04-01", "value" => 165.1 },
      { "vectorId" => 41690973, "refPer" => "2026-05-01", "value" => 165.7 }
    ])

    counts = @raw_ingestion.statcan_econ_loader.load(json_content: body)

    assert_equal 2, counts[:inserted]
    assert_equal 2, counts[:promoted]

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    may = Warehouse::CanonicalObservation.find_by!(
      measure_id: cpi.id, jurisdiction_id: canada.id, period_start: Date.new(2026, 5, 1)
    )
    assert_equal 165.7, may.value_numeric
    assert_equal "month", may.period_basis
    assert_equal Date.new(2026, 5, 31), may.period_end
    assert_equal 2026, may.measurement_year
  end

  test "loads quarterly vectors as one observation per quarter" do
    unit = Warehouse::Unit.find_or_create_by!(symbol: "$M") do |u|
      u.kind = "absolute"
      u.base_unit = "dollars"
      u.scale = 1_000_000.0
      u.currency_code = "CAD"
    end
    fdi = Warehouse::Measure.find_or_create_by!(organization_id: nil, slug: "fdi-inflows") do |m|
      m.canonical_name = "Foreign direct investment in Canada, total net flows ($M, quarterly)"
      m.unit = unit
      m.aggregation_type = "non_aggregable"
      m.frequency = "quarterly"
    end

    body = JSON.generate([
      { "vectorId" => 61913923, "refPer" => "2025-10-01", "value" => 24519.0 },
      { "vectorId" => 61913923, "refPer" => "2026-01-01", "value" => 20133.0 }
    ])

    counts = @raw_ingestion.statcan_econ_loader.load(json_content: body)

    assert_equal 2, counts[:inserted]
    assert_equal 2, counts[:promoted]

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    q4 = Warehouse::CanonicalObservation.find_by!(
      measure_id: fdi.id, jurisdiction_id: canada.id, period_start: Date.new(2025, 10, 1)
    )
    assert_equal 24519.0, q4.value_numeric
    assert_equal "quarter", q4.period_basis
    assert_equal Date.new(2025, 12, 31), q4.period_end
    assert_equal 2025, q4.measurement_year
    assert Warehouse::CanonicalObservation.exists?(
      measure_id: fdi.id, jurisdiction_id: canada.id, period_start: Date.new(2026, 1, 1)
    )
  end

  test "computes net debt excluding CPP/QPP as a share of GDP per quarter" do
    unit = Warehouse::Unit.find_or_create_by!(symbol: "%") do |u|
      u.kind = "ratio"
      u.base_unit = "ratio"
    end
    measure = Warehouse::Measure.find_or_create_by!(organization_id: nil, slug: "govt-net-debt-excl-pension-to-gdp") do |m|
      m.canonical_name = "General government net debt excluding CPP/QPP to GDP (Canada, %)"
      m.unit = unit
      m.aggregation_type = "non_aggregable"
      m.frequency = "quarterly"
    end

    body = JSON.generate([
      # 2026-Q1: complete — all three vectors present.
      { "vectorId" => 52531052, "refPer" => "2026-01-01", "value" => -538133.0 },
      { "vectorId" => 52531280, "refPer" => "2026-01-01", "value" => 951885.0 },
      { "vectorId" => 62305783, "refPer" => "2026-01-01", "value" => 3321588.0 },
      # 2025-Q4: missing the GDP vector — skipped rather than emitting a partial.
      { "vectorId" => 52531052, "refPer" => "2025-10-01", "value" => -514934.0 },
      { "vectorId" => 52531280, "refPer" => "2025-10-01", "value" => 884620.0 }
    ])

    counts = @raw_ingestion.statcan_econ_loader.load(json_content: body)

    assert_equal 1, counts[:inserted]

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    q1 = Warehouse::CanonicalObservation.find_by!(
      measure_id: measure.id, jurisdiction_id: canada.id, period_start: Date.new(2026, 1, 1)
    )
    # -(-538133 - 951885) / 3321588 * 100
    assert_in_delta 44.859, q1.value_numeric, 0.001
    assert_equal "quarter", q1.period_basis

    refute Warehouse::CanonicalObservation.exists?(
      measure_id: measure.id, jurisdiction_id: canada.id, period_start: Date.new(2025, 10, 1)
    )
  end

  test "marks the ingestion failed and re-raises on bad payloads" do
    assert_raises(JSON::ParserError) do
      @raw_ingestion.statcan_econ_loader.load(json_content: "not json")
    end

    assert_equal "failed", @raw_ingestion.reload.status
    assert @raw_ingestion.error_message.present?
  end
end
