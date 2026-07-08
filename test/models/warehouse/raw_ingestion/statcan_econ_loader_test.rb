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

  test "marks the ingestion failed and re-raises on bad payloads" do
    assert_raises(JSON::ParserError) do
      @raw_ingestion.statcan_econ_loader.load(json_content: "not json")
    end

    assert_equal "failed", @raw_ingestion.reload.status
    assert @raw_ingestion.error_message.present?
  end
end
