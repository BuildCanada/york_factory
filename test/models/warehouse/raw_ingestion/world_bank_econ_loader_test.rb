require "test_helper"

class Warehouse::RawIngestion::WorldBankEconLoaderTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(4)

    unit = Warehouse::Unit.find_or_create_by!(symbol: "intl_$") do |u|
      u.kind = "absolute"
      u.base_unit = "dollars"
    end
    @measure = Warehouse::Measure.find_or_create_by!(organization_id: nil, slug: "gdp-per-capita-ppp") do |m|
      m.canonical_name = "GDP per capita, PPP"
      m.unit = unit
      m.aggregation_type = "non_aggregable"
      m.frequency = "annual"
    end

    [ [ "USA", "United States", "national" ], [ "OECD", "OECD (average)", "supranational" ],
      [ "G7", "G7 (average)", "supranational" ], [ "INTL", "International", "supranational" ] ].each do |code, name, level|
      Warehouse::Jurisdiction.find_or_create_by!(code: code) do |j|
        j.name = name
        j.slug = code.downcase
        j.level = level
        j.fiscal_year_start_month = 1
        j.default_currency = "USD"
      end
    end

    source = Warehouse::Source.create!(
      name: "econ_worldbank_test_#{suffix}",
      url: "https://api.worldbank.org/v2/country/CAN;USA/indicator/NY.GDP.PCAP.PP.KD?format=json",
      format: "worldbank_json"
    )
    @raw_ingestion = source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/#{suffix}.json",
      checksum: SecureRandom.hex(32),
      status: :pending
    )
  end

  test "loads World Bank rows into promoted observations and completes the ingestion" do
    body = JSON.generate([
      wb_row("CAN", "2020", 45_000.0),
      wb_row("USA", "2020", 63_000.0),
      wb_row("USA", "2021", nil),
      wb_row("USA", "2019", 60_000.0, indicator: "SOME.OTHER.INDICATOR")
    ])

    counts = @raw_ingestion.world_bank_econ_loader.load(json_content: body)

    assert_equal 2, counts[:inserted]
    assert_equal 2, counts[:promoted]
    assert_equal "complete", @raw_ingestion.reload.status

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    assert Warehouse::CanonicalObservation.exists?(
      measure_id: @measure.id, jurisdiction_id: canada.id, measurement_year: 2020, value_numeric: 45_000.0
    )
  end

  test "marks the ingestion failed and re-raises on bad payloads" do
    assert_raises(JSON::ParserError) do
      @raw_ingestion.world_bank_econ_loader.load(json_content: "not json")
    end

    assert_equal "failed", @raw_ingestion.reload.status
    assert @raw_ingestion.error_message.present?
  end

  private

  def wb_row(country, year, value, indicator: "NY.GDP.PCAP.PP.KD")
    {
      "indicator" => { "id" => indicator, "value" => "GDP per capita, PPP" },
      "country" => { "id" => country, "value" => country },
      "countryiso3code" => country,
      "date" => year,
      "value" => value
    }
  end
end
