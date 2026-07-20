require "csv"

# Loads IRCC "Permanent Residents - Monthly Updates" admissions by
# province/territory and immigration category into dashboard measures via
# Warehouse::Economy::ObservationWriter.
#
# The file (ODP-PR-PT_IMMCAT.csv) is tab-separated despite the .csv
# extension, UTF-8 with BOM, bilingual (EN_*/FR_* columns), and one row per
# (month, province, category component). We sum the TOTAL column across
# provinces and components into one Canada-wide monthly value per main
# category, plus an all-categories total. IRCC suppresses values below 6
# (shown as "--", counted as zero here) and rounds everything else to the
# nearest 5, so sums are approximate by design.
class Warehouse::RawIngestion::IrccAdmissionsLoader < ActiveRecord::AssociatedObject
  performs :load

  # EN_IMMIGRATION_CATEGORY-MAIN_CATEGORY -> canonical measure slug
  # (db/seeds/kpis/population_measures.yml)
  CATEGORY_MEASURES = {
    "Economic" => "pr-admissions-economic",
    "Sponsored Family" => "pr-admissions-family",
    "Resettled Refugee & Protected Person in Canada" => "pr-admissions-refugee",
    "All Other Immigration" => "pr-admissions-other"
  }.freeze
  TOTAL_MEASURE = "pr-admissions-total".freeze

  YEAR_COLUMN = "EN_YEAR".freeze
  MONTH_COLUMN = "EN_MONTH".freeze
  CATEGORY_COLUMN = "EN_IMMIGRATION_CATEGORY-MAIN_CATEGORY".freeze
  VALUE_COLUMN = "TOTAL".freeze

  def load(csv_content:)
    content = csv_content.dup.force_encoding(Encoding::UTF_8)
    content = content.scrub unless content.valid_encoding?
    # The delete_prefix argument is a literal U+FEFF byte-order mark.
    rows = CSV.parse(content.delete_prefix("﻿"), col_sep: "\t", headers: true, liberal_parsing: true)

    totals = Hash.new(0)
    unmapped_categories = Set.new

    rows.each do |row|
      month = parse_month(row[YEAR_COLUMN], row[MONTH_COLUMN])
      value = parse_value(row[VALUE_COLUMN])
      next if month.nil? || value.nil?

      measure_slug = CATEGORY_MEASURES[row[CATEGORY_COLUMN]&.strip]
      if measure_slug.nil?
        unmapped_categories << row[CATEGORY_COLUMN]
      else
        totals[[ measure_slug, month ]] += value
      end
      totals[[ TOTAL_MEASURE, month ]] += value
    end

    if unmapped_categories.any?
      Rails.logger.warn "[IrccAdmissionsLoader] Unmapped immigration categories " \
        "(counted in total only): #{unmapped_categories.to_a.inspect}"
    end

    tuples = totals.map do |(measure_slug, month), value|
      {
        measure_slug: measure_slug,
        country_code: "CAN",
        year: month.year.to_s,
        period: month.iso8601,
        value: value
      }
    end

    counts = Warehouse::Economy::ObservationWriter.new(raw_ingestion: raw_ingestion).write(tuples)

    raw_ingestion.update!(status: "complete")
    Rails.logger.info "[IrccAdmissionsLoader] #{raw_ingestion.source.name}: #{counts.inspect}"
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  def parse_month(year, month_abbr)
    Date.strptime("#{year} #{month_abbr}", "%Y %b")
  rescue ArgumentError, TypeError
    nil
  end

  # Values are integer counts; "--" marks suppressed cells (0-5), which count
  # as zero so suppressed rows still anchor the month in sparse categories.
  def parse_value(raw)
    value = raw.to_s.strip.delete(",")
    return 0 if value == "--"
    return nil unless value.match?(/\A\d+\z/)

    Integer(value)
  end
end
