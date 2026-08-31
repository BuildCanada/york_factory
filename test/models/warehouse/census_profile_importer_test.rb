require "test_helper"

class Warehouse::CensusProfileImporterTest < ActiveSupport::TestCase
  test "imports versioned 2021 CSD population rows idempotently" do
    csv = <<~CSV
      CENSUS_YEAR,DGUID,ALT_GEO_CODE,GEO_LEVEL,GEO_NAME,TNR_SF,TNR_LF,DATA_QUALITY_FLAG,CHARACTERISTIC_ID,CHARACTERISTIC_NAME,CHARACTERISTIC_NOTE,C1_COUNT_TOTAL
      2021,2021A00054811061,4811061,Census subdivision,Edmonton,0,0,0,1,"Population, 2021",1,1010899
      2021,2021A00054811061,4811061,Census subdivision,Edmonton,0,0,0,2,"Population, 2016",1,932546
      2021,2021A00054811061,4811061,Census subdivision,Edmonton,0,0,0,6,"Population density per square kilometre",1,1320.4
      2021,2021A00054811061,4811061,Census subdivision,Edmonton,0,0,0,7,"Land area in square kilometres",1,765.61
    CSV

    Dir.mktmpdir do |dir|
      source = Pathname(dir).join(Warehouse::CensusProfileImporter::CSV_ENTRY)
      source.write(csv)
      archive = Pathname(dir).join("profile.zip")
      system("zip", "-q", archive.to_s, source.basename.to_s, chdir: dir)
      sha = Digest::SHA256.file(archive).hexdigest
      importer = Warehouse::CensusProfileImporter.new(
        zip_path: archive, expected_sha256: sha, retrieved_at: Time.utc(2026, 8, 29)
      )

      2.times { importer.import! }

      profile = Warehouse::CensusProfile.sole
      assert_equal 1_010_899, profile.population
      assert_equal "4811061", profile.geo_uid
      assert_equal BigDecimal("765.61"), profile.area_sq_km
      assert_equal BigDecimal("1320.4"), profile.population_density_per_sq_km
    end
  end
end
