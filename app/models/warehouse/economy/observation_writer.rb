# Shared writer for economy dashboard loaders (World Bank, OECD, ...).
#
# Loaders parse their source format down to normalized tuples
#   { measure_slug:, country_code:, year:, value: }
# and this writer does everything stateful: resolves measures and country
# jurisdictions, creates a per-ingestion KpiDocument (vintage anchor), bulk
# upserts extracted_observations, auto-promotes them to canonical (trusted
# machine-ingested statistics), and computes the G7 average series.
class Warehouse::Economy::ObservationWriter
  APPROVED_BY = "economy-importer".freeze
  BATCH_SIZE = 1_000

  # Jurisdiction codes (warehouse.jurisdictions.code) of G7 members. The G7
  # average is an unweighted mean, computed only for years where all seven
  # members report a value, and stored with status "estimated".
  G7_JURISDICTION_CODES = %w[CA USA GBR FRA DEU ITA JPN].freeze

  # Source country codes -> warehouse.jurisdictions.code. World Bank uses
  # ISO3 with OED for the OECD-members aggregate; OECD SDMX uses ISO3 with
  # OECD for its average. Canada maps onto the existing federal CA row.
  COUNTRY_CODES = {
    "CAN" => "CA",
    "USA" => "USA",
    "GBR" => "GBR",
    "FRA" => "FRA",
    "DEU" => "DEU",
    "ITA" => "ITA",
    "JPN" => "JPN",
    "OED" => "OECD",
    "OECD" => "OECD"
  }.freeze

  def initialize(raw_ingestion:)
    @raw_ingestion = raw_ingestion
    @source = raw_ingestion.source
  end

  def write(tuples)
    counts = { inserted: 0, promoted: 0, g7_rows: 0, skipped: 0 }
    measures = measures_by_slug(tuples)
    jurisdictions = jurisdictions_by_code

    ActiveRecord::Base.transaction do
      document = find_or_create_document!(jurisdictions.fetch("INTL"))

      rows, counts[:skipped] = build_rows(tuples, measures, jurisdictions, document)
      g7_rows = build_g7_rows(rows, jurisdictions)
      counts[:g7_rows] = g7_rows.size

      (rows + g7_rows).each_slice(BATCH_SIZE) do |batch|
        counts[:inserted] += Warehouse::ExtractedObservation.insert_all(
          batch,
          unique_by: :idx_extracted_observations_unique
        ).rows.length
      end

      counts[:promoted] = promote_document_observations!(document, jurisdictions)
    end

    counts
  end

  private

  attr_reader :raw_ingestion, :source

  def measures_by_slug(tuples)
    slugs = tuples.map { |t| t[:measure_slug] }.uniq
    Warehouse::Measure.canonical.where(slug: slugs).index_by(&:slug)
  end

  def jurisdictions_by_code
    codes = COUNTRY_CODES.values + %w[G7 INTL]
    Warehouse::Jurisdiction.where(code: codes.uniq).index_by(&:code)
  end

  # One document per ingestion: document_id is part of the observation unique
  # index, so each new fetch (new checksum) gets fresh rows with a later
  # vintage_date, and measure_facts surfaces the latest vintage per series.
  def find_or_create_document!(intl_jurisdiction)
    fetched_on = raw_ingestion.fetched_at.to_date

    Warehouse::KpiDocument.find_or_create_by!(
      doc_url: "#{source.url}#ingestion-#{raw_ingestion.checksum.first(12)}"
    ) do |doc|
      doc.jurisdiction_id = intl_jurisdiction.id
      doc.raw_ingestion_id = raw_ingestion.id
      doc.fiscal_year = fetched_on.year
      doc.published_at = fetched_on
      doc.published_at_source = "discovered_at_fallback"
      doc.doc_title = "#{source.name} (fetched #{fetched_on.iso8601})"
      doc.doc_type = "api_snapshot"
      doc.source_page_url = source.url
    end
  end

  def build_rows(tuples, measures, jurisdictions, document)
    skipped = 0
    now = Time.current

    rows = tuples.filter_map do |tuple|
      measure = measures[tuple[:measure_slug]]
      jurisdiction = jurisdictions[COUNTRY_CODES[tuple[:country_code]]]
      year = tuple[:year].to_i
      value = tuple[:value]

      if measure.nil? || jurisdiction.nil? || value.nil? || year.zero?
        skipped += 1
        next
      end

      {
        measure_id: measure.id,
        measurement_year: year,
        value_type: "actual",
        value_numeric: value.to_f,
        period_basis: "full_year",
        period_start: Date.new(year, 1, 1),
        period_end: Date.new(year, 12, 31),
        period_type: "calendar_year",
        jurisdiction_id: jurisdiction.id,
        document_id: document.id,
        review_status: "pending",
        created_at: now,
        updated_at: now
      }
    end

    [ rows, skipped ]
  end

  def build_g7_rows(rows, jurisdictions)
    g7 = jurisdictions["G7"]
    return [] if g7.nil?

    members = jurisdictions.values_at(*G7_JURISDICTION_CODES).compact
    return [] unless members.size == G7_JURISDICTION_CODES.size
    member_ids = members.map(&:id)

    rows
      .select { |r| member_ids.include?(r[:jurisdiction_id]) }
      .group_by { |r| [ r[:measure_id], r[:measurement_year] ] }
      .filter_map do |_, member_rows|
        next unless member_rows.map { |r| r[:jurisdiction_id] }.uniq.size == member_ids.size
        values = member_rows.map { |r| r[:value_numeric] }
        member_rows.first.merge(
          jurisdiction_id: g7.id,
          value_numeric: values.sum / values.size
        )
      end
  end

  def promote_document_observations!(document, jurisdictions)
    g7_id = jurisdictions["G7"]&.id
    vintage_date = raw_ingestion.fetched_at.to_date
    promoted = 0

    Warehouse::ExtractedObservation.where(document_id: document.id).find_each do |observation|
      observation.promote_to_canonical!(
        approved_by: APPROVED_BY,
        status: observation.jurisdiction_id == g7_id ? "estimated" : "reported",
        vintage_date: vintage_date
      )
      promoted += 1
    end

    promoted
  end
end
