require "test_helper"

class Warehouse::RawIngestion::OwidEconLoaderTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(4)

    unit = Warehouse::Unit.find_or_create_by!(symbol: "score") do |u|
      u.kind = "ratio"
      u.base_unit = "ratio"
    end
    @measure = Warehouse::Measure.find_or_create_by!(organization_id: nil, slug: "life-satisfaction") do |m|
      m.canonical_name = "Self-reported life satisfaction (0-10)"
      m.unit = unit
      m.aggregation_type = "non_aggregable"
      m.frequency = "annual"
    end

    [ [ "USA", "United States", "national" ], [ "G7", "G7 (average)", "supranational" ],
      [ "INTL", "International", "supranational" ] ].each do |code, name, level|
      Warehouse::Jurisdiction.find_or_create_by!(code: code) do |j|
        j.name = name
        j.slug = code.downcase
        j.level = level
        j.fiscal_year_start_month = 1
        j.default_currency = "USD"
      end
    end

    source = Warehouse::Source.create!(
      name: "econ_owid_life_satisfaction",
      url: "https://ourworldindata.org/grapher/happiness-cantril-ladder.csv",
      format: "csv"
    )
    @raw_ingestion = source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/#{suffix}.csv",
      checksum: SecureRandom.hex(32),
      status: :pending
    )
  end

  test "loads OWID grapher rows, skipping aggregates without ISO3 codes" do
    csv = <<~CSV
      Entity,Code,Year,Cantril ladder score
      Canada,CAN,2022,7.02
      Canada,CAN,2023,6.90
      United States,USA,2023,6.72
      World,OWID_WRL,2023,5.55
      Africa,,2023,4.40
    CSV

    counts = @raw_ingestion.owid_econ_loader.load(csv_content: csv)

    # OWID_WRL passes the loader but is dropped by ObservationWriter's
    # COUNTRY_CODES mapping (counted as skipped).
    assert_equal 3, counts[:inserted]
    assert_equal 1, counts[:skipped]
    assert_equal "complete", @raw_ingestion.reload.status

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    assert Warehouse::CanonicalObservation.exists?(
      measure_id: @measure.id, jurisdiction_id: canada.id, measurement_year: 2023, value_numeric: 6.90
    )
  end

  test "handles binary-encoded payloads with multibyte headers" do
    csv = (+"Entity,Code,Year,CO₂ emissions per capita\nCanada,CAN,2024,13.42\n")
      .force_encoding(Encoding::BINARY)

    counts = @raw_ingestion.owid_econ_loader.load(csv_content: csv)

    assert_equal 1, counts[:inserted]
    assert_equal "complete", @raw_ingestion.reload.status
  end

  test "marks the ingestion failed and re-raises when there is no value column" do
    assert_raises(RuntimeError) do
      @raw_ingestion.owid_econ_loader.load(csv_content: "Entity,Code,Year\nCanada,CAN,2023\n")
    end

    assert_equal "failed", @raw_ingestion.reload.status
  end
end
