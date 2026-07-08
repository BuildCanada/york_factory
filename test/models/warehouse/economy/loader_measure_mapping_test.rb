require "test_helper"

# Every measure slug referenced by an economy-pipeline loader mapping must be
# seeded by db/seeds/kpis/*_measures.yml — otherwise ObservationWriter silently
# skips all of that loader's tuples at import time.
class Warehouse::Economy::LoaderMeasureMappingTest < ActiveSupport::TestCase
  MEASURE_FILES = Dir.glob(Rails.root.join("db/seeds/kpis/*_measures.yml")).sort.freeze

  SEEDED_SLUGS = MEASURE_FILES.flat_map { |file|
    YAML.safe_load_file(file, aliases: true)
      .fetch("measures").map { |m| m.fetch("slug") }
  }.freeze

  test "World Bank loader slugs are all seeded" do
    assert_empty Warehouse::RawIngestion::WorldBankEconLoader::INDICATORS.values - SEEDED_SLUGS
  end

  test "OECD loader slugs are all seeded" do
    assert_empty Warehouse::RawIngestion::OecdSdmxLoader::SOURCES.values - SEEDED_SLUGS
  end

  test "StatCan loader slugs are all seeded" do
    assert_empty Warehouse::RawIngestion::StatcanEconLoader::VECTORS.values - SEEDED_SLUGS
  end

  test "OWID loader slugs are all seeded" do
    assert_empty Warehouse::RawIngestion::OwidEconLoader::SOURCES.values - SEEDED_SLUGS
  end

  test "measure slugs are globally unique across seed files" do
    duplicates = SEEDED_SLUGS.tally.select { |_, count| count > 1 }.keys
    assert_empty duplicates
  end

  test "seeded measure units all exist in units.yml" do
    unit_symbols = YAML.safe_load_file(Rails.root.join("db/seeds/kpis/units.yml"), aliases: true)
      .fetch("units").map { |u| u.fetch("symbol") }

    MEASURE_FILES.each do |file|
      YAML.safe_load_file(file, aliases: true)
        .fetch("measures").each do |measure|
          assert_includes unit_symbols, measure.fetch("unit"),
            "#{File.basename(file)}: measure #{measure["slug"]} references unknown unit #{measure["unit"]}"
        end
    end
  end
end
