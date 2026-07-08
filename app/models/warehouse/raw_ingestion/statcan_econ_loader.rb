# Loads Statistics Canada WDS vector payloads (normalized by
# Source::Fetcher::StatcanVectors to a flat JSON array) into welfare dashboard
# measures via Warehouse::Economy::ObservationWriter. All StatCan vectors are
# Canada-only annual series.
class Warehouse::RawIngestion::StatcanEconLoader < ActiveRecord::AssociatedObject
  performs :load

  # StatCan vector id -> canonical measure slug
  # (db/seeds/kpis/welfare_measures.yml and housing_measures.yml)
  VECTORS = {
    96439638 => "gini-after-tax-canada",
    96730402 => "low-income-entry-rate",
    96730403 => "low-income-exit-rate",
    730579 => "housing-starts-canada",
    733334 => "rental-vacancy-rate-canada",
    44312461 => "crime-severity-index",
    44407600 => "police-reported-crime-rate"
  }.freeze

  def load(json_content:)
    rows = JSON.parse(json_content)

    tuples = rows.filter_map do |row|
      measure_slug = VECTORS[row["vectorId"]]
      next if measure_slug.nil? || row["value"].nil?

      {
        measure_slug: measure_slug,
        country_code: "CAN",
        year: row.fetch("refPer").to_s.first(4),
        value: row["value"]
      }
    end

    counts = Warehouse::Economy::ObservationWriter.new(raw_ingestion: raw_ingestion).write(tuples)

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[StatcanEconLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end
end
