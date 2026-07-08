require "test_helper"

class Warehouse::Economy::ObservationWriterTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(4)

    @unit = Warehouse::Unit.create!(symbol: "intl_$-#{suffix}", kind: "absolute", base_unit: "dollars")
    @measure = Warehouse::Measure.create!(
      organization_id: nil,
      slug: "gdp-test-#{suffix}",
      canonical_name: "GDP test #{suffix}",
      unit: @unit,
      aggregation_type: "non_aggregable",
      frequency: "annual"
    )

    [
      [ "USA", "United States", "national" ],
      [ "GBR", "United Kingdom", "national" ],
      [ "FRA", "France", "national" ],
      [ "DEU", "Germany", "national" ],
      [ "ITA", "Italy", "national" ],
      [ "JPN", "Japan", "national" ],
      [ "OECD", "OECD (average)", "supranational" ],
      [ "G7", "G7 (average)", "supranational" ],
      [ "INTL", "International", "supranational" ]
    ].each do |code, name, level|
      Warehouse::Jurisdiction.find_or_create_by!(code: code) do |j|
        j.name = name
        j.slug = code.downcase
        j.level = level
        j.fiscal_year_start_month = 1
        j.default_currency = "USD"
      end
    end

    @source = Warehouse::Source.create!(
      name: "econ_worldbank_test_#{suffix}",
      url: "https://api.worldbank.org/v2/country/all/indicator/TEST",
      format: "worldbank_json"
    )
    @raw_ingestion = @source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/#{suffix}.json",
      checksum: SecureRandom.hex(32),
      status: :pending
    )
  end

  test "writes tuples as promoted canonical observations per country" do
    counts = writer.write([
      tuple(country_code: "CAN", year: 2020, value: 45_000.5),
      tuple(country_code: "USA", year: 2020, value: 63_000.0)
    ])

    assert_equal 2, counts[:inserted]
    assert_equal 2, counts[:promoted]
    assert_equal 0, counts[:g7_rows]
    assert_equal 0, counts[:skipped]

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    observation = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measure.id, jurisdiction_id: canada.id, measurement_year: 2020
    )
    assert_equal 45_000.5, observation.value_numeric
    assert_equal "reported", observation.status
    assert_equal "economy-importer", observation.approved_by
    assert_equal "actual", observation.value_type
    assert_equal "full_year", observation.period_basis
  end

  test "rerunning the same write is idempotent" do
    tuples = [ tuple(country_code: "CAN", year: 2021, value: 46_000.0) ]

    writer.write(tuples)
    counts = writer.write(tuples)

    assert_equal 0, counts[:inserted]
    assert_equal 1, Warehouse::ExtractedObservation.where(measure_id: @measure.id).count
    assert_equal 1, Warehouse::CanonicalObservation.where(measure_id: @measure.id).count
  end

  test "computes G7 average only for years where all seven members report" do
    complete_year = %w[CAN USA GBR FRA DEU ITA JPN].map.with_index do |code, i|
      tuple(country_code: code, year: 2019, value: 100.0 + i)
    end
    incomplete_year = %w[CAN USA].map { |code| tuple(country_code: code, year: 2020, value: 50.0) }

    counts = writer.write(complete_year + incomplete_year)

    assert_equal 1, counts[:g7_rows]
    g7 = Warehouse::Jurisdiction.find_by!(code: "G7")
    g7_observation = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measure.id, jurisdiction_id: g7.id, measurement_year: 2019
    )
    assert_in_delta 103.0, g7_observation.value_numeric
    assert_equal "estimated", g7_observation.status
    assert_nil Warehouse::CanonicalObservation.find_by(
      measure_id: @measure.id, jurisdiction_id: g7.id, measurement_year: 2020
    )
  end

  test "skips unknown country codes, unknown measures, and nil values" do
    counts = writer.write([
      tuple(country_code: "BRA", year: 2020, value: 1.0),
      tuple(country_code: "CAN", year: 2020, value: nil),
      { measure_slug: "no-such-measure", country_code: "CAN", year: 2020, value: 1.0 }
    ])

    assert_equal 0, counts[:inserted]
    assert_equal 3, counts[:skipped]
  end

  test "a new ingestion creates a new document so revisions get a later vintage" do
    writer.write([ tuple(country_code: "CAN", year: 2022, value: 10.0) ])

    second_ingestion = @source.raw_ingestions.create!(
      fetched_at: Time.current + 1.day,
      raw_file_path: "raw/test/second.json",
      checksum: SecureRandom.hex(32),
      status: :pending
    )
    Warehouse::Economy::ObservationWriter
      .new(raw_ingestion: second_ingestion)
      .write([ tuple(country_code: "CAN", year: 2022, value: 11.0) ])

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    facts = Warehouse::MeasureFact.where(measure_id: @measure.id, jurisdiction_id: canada.id, measurement_year: 2022)
    assert_equal 1, facts.count
    assert_equal 11.0, facts.first.value_numeric
  end

  private

  def writer
    Warehouse::Economy::ObservationWriter.new(raw_ingestion: @raw_ingestion)
  end

  def tuple(country_code:, year:, value:)
    { measure_slug: @measure.slug, country_code: country_code, year: year, value: value }
  end
end
