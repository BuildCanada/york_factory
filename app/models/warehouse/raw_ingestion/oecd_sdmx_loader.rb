require "csv"

# Loads OECD SDMX csvfile payloads (one dataflow per source) into the economy
# dashboard measures via Warehouse::Economy::ObservationWriter.
#
# SDMX csvfile output is long-format CSV with one observation per row; the
# columns we rely on are REF_AREA (ISO3 country or OECD aggregate; the DAC
# dataflows call it DONOR), TIME_PERIOD (year) and OBS_VALUE.
class Warehouse::RawIngestion::OecdSdmxLoader < ActiveRecord::AssociatedObject
  performs :load

  # Source name -> canonical measure slug
  # (db/seeds/kpis/economy_measures.yml and welfare_measures.yml)
  SOURCES = {
    "econ_oecd_labour_productivity" => "labour-productivity-gdp-per-hour",
    "econ_oecd_real_minimum_wage" => "real-minimum-wage-ppp",
    "econ_oecd_hours_worked" => "average-annual-hours-worked",
    "econ_oecd_household_debt" => "household-debt-to-income",
    "econ_oecd_house_price_to_income" => "house-price-to-income",
    "econ_oecd_real_house_prices" => "real-house-price-index",
    "econ_oecd_oda" => "oda-pct-gni"
  }.freeze

  def load(csv_content:)
    measure_slug = SOURCES.fetch(raw_ingestion.source.name) do
      raise "No measure mapping for OECD source: #{raw_ingestion.source.name}"
    end

    tuples = CSV.parse(csv_content, headers: true, liberal_parsing: true).filter_map do |row|
      value = row["OBS_VALUE"]
      year = row["TIME_PERIOD"]
      next if value.blank? || year.blank?

      {
        measure_slug: measure_slug,
        country_code: row["REF_AREA"] || row["DONOR"],
        year: year,
        value: value
      }
    end

    counts = Warehouse::Economy::ObservationWriter.new(raw_ingestion: raw_ingestion).write(tuples)

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[OecdSdmxLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end
end
