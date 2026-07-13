require "csv"

# Loads Our World in Data grapher CSV payloads into dashboard measures via
# Warehouse::Economy::ObservationWriter.
#
# Grapher CSVs (https://ourworldindata.org/grapher/{slug}.csv) are long-format
# with columns Entity, Code, Year and one value column whose header varies per
# dataset — so we take the fourth column. Rows for aggregates (World, regions)
# carry non-ISO3 or blank codes and fall out in ObservationWriter's
# COUNTRY_CODES mapping.
class Warehouse::RawIngestion::OwidEconLoader < ActiveRecord::AssociatedObject
  performs :load

  # Source name -> canonical measure slug (db/seeds/kpis/*_measures.yml)
  SOURCES = {
    "econ_owid_life_satisfaction" => "life-satisfaction",
    "econ_owid_homicide_rate" => "homicide-rate",
    "econ_owid_corruption_perceptions" => "corruption-perceptions-index",
    "econ_owid_co2_per_capita" => "co2-emissions-per-capita"
  }.freeze

  def load(csv_content:)
    measure_slug = SOURCES.fetch(raw_ingestion.source.name) do
      raise "No measure mapping for OWID source: #{raw_ingestion.source.name}"
    end

    # HTTPX hands the body over as BINARY; OWID files are UTF-8 (headers can
    # contain multibyte characters like "CO\u2082").
    content = csv_content.dup.force_encoding(Encoding::UTF_8)
    content = content.scrub unless content.valid_encoding?
    rows = CSV.parse(content.delete_prefix("\uFEFF"), headers: true, liberal_parsing: true)
    value_column = rows.headers[3] or raise "OWID CSV has no value column"

    tuples = rows.filter_map do |row|
      value = row[value_column]
      next if value.blank? || row["Code"].blank? || row["Year"].blank?

      {
        measure_slug: measure_slug,
        country_code: row["Code"],
        year: row["Year"],
        value: value
      }
    end

    counts = Warehouse::Economy::ObservationWriter.new(raw_ingestion: raw_ingestion).write(tuples)

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[OwidEconLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end
end
