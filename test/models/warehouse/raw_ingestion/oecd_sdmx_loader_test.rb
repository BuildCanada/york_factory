require "test_helper"

class Warehouse::RawIngestion::OecdSdmxLoaderTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(4)

    unit = Warehouse::Unit.find_or_create_by!(symbol: "intl_$_per_hour") do |u|
      u.kind = "rate"
      u.base_unit = "dollars"
      u.denominator_unit = "hours"
      u.denominator_scale = 1.0
    end
    @measure = Warehouse::Measure.find_or_create_by!(organization_id: nil, slug: "labour-productivity-gdp-per-hour") do |m|
      m.canonical_name = "GDP per hour worked"
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
      name: "econ_oecd_labour_productivity",
      url: "https://sdmx.oecd.org/public/rest/data/OECD.SDD.TPS,DSD_PDB@DF_PDB,/CAN.A.GDPHRS?format=csvfile",
      format: "csv"
    )
    @raw_ingestion = source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/#{suffix}.csv",
      checksum: SecureRandom.hex(32),
      status: :pending
    )
  end

  test "loads SDMX csvfile rows into promoted observations" do
    csv = <<~CSV
      DATAFLOW,REF_AREA,FREQ,MEASURE,ACTIVITY,UNIT_MEASURE,PRICE_BASE,TRANSFORMATION,ASSET_CODE,CONVERSION_TYPE,TIME_PERIOD,OBS_VALUE,OBS_STATUS,UNIT_MULT,BASE_PER,DECIMALS
      OECD.SDD.TPS:DSD_PDB@DF_PDB(2.0),CAN,A,GDPHRS,_T,USD_PPP_H,LR,N,_Z,PPP,2020,60.5,A,0,2020,2
      OECD.SDD.TPS:DSD_PDB@DF_PDB(2.0),USA,A,GDPHRS,_T,USD_PPP_H,LR,N,_Z,PPP,2020,74.2,A,0,2020,2
      OECD.SDD.TPS:DSD_PDB@DF_PDB(2.0),OECD,A,GDPHRS,_T,USD_PPP_H,LR,N,_Z,PPP,2020,,M,0,2020,2
    CSV

    counts = @raw_ingestion.oecd_sdmx_loader.load(csv_content: csv)

    assert_equal 2, counts[:inserted]
    assert_equal "complete", @raw_ingestion.reload.status

    canada = Warehouse::Jurisdiction.find_by!(code: "CA")
    observation = Warehouse::CanonicalObservation.find_by!(
      measure_id: @measure.id, jurisdiction_id: canada.id, measurement_year: 2020
    )
    assert_equal 60.5, observation.value_numeric
    assert_equal "reported", observation.status
  end

  test "raises for a source with no measure mapping and marks the ingestion failed" do
    @raw_ingestion.source.update!(name: "econ_oecd_unmapped_#{SecureRandom.hex(4)}")

    error = assert_raises(RuntimeError) do
      @raw_ingestion.oecd_sdmx_loader.load(csv_content: "REF_AREA,TIME_PERIOD,OBS_VALUE\n")
    end
    assert_match(/No measure mapping/, error.message)
    assert_equal "failed", @raw_ingestion.reload.status
  end
end
