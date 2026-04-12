require "test_helper"

class Warehouse::RawIngestion::PopulationLoaderTest < ActiveSupport::TestCase
  setup do
    @source = Warehouse::Source.find_or_create_by!(name: "statcan_da_population") do |s|
      s.url = "https://example.com/pop.csv"
      s.format = "csv"
      s.fetch_frequency = "manual"
    end
    @ingestion = Warehouse::RawIngestion.create!(source: @source, fetched_at: Time.current, raw_file_path: "test/pop", checksum: "pop123", status: :pending)

    @da1 = Warehouse::GeoBoundary.create!(boundary_type: "da", geo_uid: "35010001", census_year: 2021)
    @da2 = Warehouse::GeoBoundary.create!(boundary_type: "da", geo_uid: "35010002", census_year: 2021)
  end

  test "updates DA populations from CSV with DAUID column" do
    csv = <<~CSV
      DAUID,POPULATION
      35010001,1500
      35010002,2300
    CSV

    @ingestion.population_loader.load(csv_content: csv)

    assert_equal 1500, @da1.reload.population
    assert_equal 2300, @da2.reload.population
    assert_equal "complete", @ingestion.reload.status
  end

  test "updates DA populations from CSV with ALT_GEO_CODE column" do
    csv = <<~CSV
      ALT_GEO_CODE,T_DATA_DONNEE
      35010001,1500
    CSV

    @ingestion.population_loader.load(csv_content: csv)
    assert_equal 1500, @da1.reload.population
  end

  test "skips rows with missing DA UID" do
    csv = <<~CSV
      DAUID,POPULATION
      ,1500
      35010002,2300
    CSV

    @ingestion.population_loader.load(csv_content: csv)
    assert_nil @da1.reload.population
    assert_equal 2300, @da2.reload.population
  end

  test "skips rows with zero or negative population" do
    csv = <<~CSV
      DAUID,POPULATION
      35010001,0
      35010002,-5
    CSV

    @ingestion.population_loader.load(csv_content: csv)
    assert_nil @da1.reload.population
    assert_nil @da2.reload.population
  end

  test "completes with warning for empty CSV" do
    csv = <<~CSV
      DAUID,POPULATION
    CSV

    @ingestion.population_loader.load(csv_content: csv)
    assert_equal "complete", @ingestion.reload.status
  end

  test "silently ignores unknown DA UIDs" do
    csv = <<~CSV
      DAUID,POPULATION
      99999999,1500
      35010001,2300
    CSV

    @ingestion.population_loader.load(csv_content: csv)
    assert_equal 2300, @da1.reload.population
  end

  test "fails ingestion on invalid input" do
    assert_raises do
      @ingestion.population_loader.load(csv_content: nil)
    end

    assert_equal "failed", @ingestion.reload.status
    assert @ingestion.error_message.present?
  end
end
