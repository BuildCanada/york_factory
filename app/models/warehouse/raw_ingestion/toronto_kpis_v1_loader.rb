require "sqlite3"

class Warehouse::RawIngestion::TorontoKpisV1Loader < ActiveRecord::AssociatedObject
  performs :load

  # Imports a v1 toronto-budgets/scrape.db snapshot into warehouse.*.
  #
  # Steps (one Postgres transaction):
  #   1. Documents:   v1 documents → warehouse.kpi_documents
  #   2. Measures:    v1 kpis      → warehouse.measures
  #   3. Citations:   v1 kpi_values → warehouse.measure_citations
  #   4. Percentage cleanup for ratio-kind units (multiply 0-1 fractions by 100)
  #
  # Idempotent: rerunning is a no-op except for new rows.

  def load
    db = SQLite3::Database.new(raw_ingestion.raw_file_path, readonly: true, results_as_hash: true)
    toronto = Warehouse::Jurisdiction.find_by!(slug: "toronto")
    counts = { documents: 0, measures: 0, citations: 0, ratio_cleanups: 0 }

    ActiveRecord::Base.transaction do
      counts[:documents] = import_documents(db, toronto)
      slug_to_unit_id = Warehouse::Unit.pluck(:symbol, :id).to_h
      v1_kpi_to_measure_id = import_measures(db, toronto, slug_to_unit_id)
      counts[:measures] = v1_kpi_to_measure_id.size
      counts[:citations], counts[:ratio_cleanups] = import_citations(db, v1_kpi_to_measure_id)
    end

    raw_ingestion.update!(status: "complete")
    counts
  rescue => e
    raw_ingestion.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  def import_documents(db, toronto)
    alias_map = build_alias_map(toronto)
    count = 0

    db.execute("SELECT * FROM documents") do |row|
      doc = Warehouse::KpiDocument.find_or_initialize_by(doc_url: row["doc_url"])
      doc.assign_attributes(
        jurisdiction_id: toronto.id,
        organization_id: alias_map[normalize_alias(row["agency_department"])],
        raw_ingestion_id: raw_ingestion.id,
        fiscal_year: row["year"],
        published_at: published_at_from_v1(row),
        published_at_source: published_at_source_from_v1(row),
        source_page_url: row["source_page"],
        doc_title: row["doc_title"],
        doc_type: row["doc_type"],
        filepath: row["filepath"]
      )
      doc.save!
      count += 1
    end

    count
  end

  def import_measures(db, toronto, unit_lookup)
    alias_map = build_alias_map(toronto)
    default_unit_id = unit_lookup.fetch("count")
    v1_to_v2_id = {}

    db.execute("SELECT * FROM kpis") do |row|
      org_id = alias_map[normalize_alias(row["agency_department"])]
      unit_id = unit_lookup[row["unit"]] || default_unit_id
      slug = parameterize(row["measure_name"])

      measure = Warehouse::Measure.find_or_initialize_by(organization_id: org_id, slug: slug)
      measure.assign_attributes(
        canonical_name: row["measure_name"],
        unit_id: unit_id,
        service_category: row["service_category"],
        description: row["description"],
        first_seen_year: row["first_seen_year"],
        last_seen_year: row["last_seen_year"]
      )
      measure.save!
      v1_to_v2_id[row["id"]] = measure.id
    end

    v1_to_v2_id
  end

  def import_citations(db, v1_kpi_to_measure_id)
    doc_id_lookup = build_v1_to_v2_doc_lookup(db)
    measure_unit = Warehouse::Measure
      .joins(:unit)
      .pluck(:id, "warehouse.units.symbol")
      .each_with_object({}) { |(id, sym), h| h[id] = sym }
    inserted = 0
    cleanups = 0
    batch = []
    batch_size = 1_000

    db.execute("SELECT * FROM kpi_values") do |row|
      measure_id = v1_kpi_to_measure_id[row["kpi_id"]]
      next unless measure_id
      document_id = doc_id_lookup[row["document_id"]]
      next unless document_id

      symbol = measure_unit[measure_id]
      raw_value = row["value_numeric"]&.to_f
      # Convention: value_numeric is stored in DISPLAY units (the unit's own
      # natural notation). unit.scale converts display → base_unit when downstream
      # code needs cross-unit math. Don't pre-multiply by scale here — the v1
      # SQLite already holds display-form values.
      cleaned_value, was_cleaned = cleanup_v1_percentage_bug(raw_value, symbol)
      cleanups += 1 if was_cleaned
      value_numeric = cleaned_value

      notes = row["notes"]
      notes = [ notes, "[v1-cleanup: x100 for fractional percentage]" ].compact.join(" ") if was_cleaned

      batch << {
        measure_id: measure_id,
        measurement_year: row["measurement_year"],
        value_type: row["value_type"],
        value_numeric: value_numeric,
        value_text: row["value_text"],
        value_raw_text: row["value_text"],
        period_basis: "full_year",
        document_id: document_id,
        page_number: row["page_number"],
        notes: notes,
        created_at: Time.current,
        updated_at: Time.current
      }

      if batch.size >= batch_size
        inserted += insert_citation_batch(batch)
        batch.clear
      end
    end

    inserted += insert_citation_batch(batch) if batch.any?
    [ inserted, cleanups ]
  end

  def insert_citation_batch(batch)
    Warehouse::MeasureCitation.insert_all(
      batch,
      unique_by: :idx_measure_citations_unique
    ).rows.length
  end

  # The v1 percentage-bug fix: a raw value of 0.05 in the "%" unit means someone
  # entered the fraction (0.05 = 5%) instead of the percentage (5 = 5%). After
  # scale=0.01 normalization the bug would be 100x smaller than truth. Detect on
  # the RAW (pre-scale) value and only for the literal "%" unit.
  def cleanup_v1_percentage_bug(raw_value, unit_symbol)
    return [ raw_value, false ] if raw_value.nil?
    return [ raw_value, false ] unless unit_symbol == "%"
    return [ raw_value, false ] unless raw_value > 0 && raw_value < 1
    [ raw_value * 100, true ]
  end

  def build_alias_map(jurisdiction)
    Warehouse::OrganizationAlias
      .joins(:organization)
      .where("warehouse.organizations.jurisdiction_id = ?", jurisdiction.id)
      .pluck(:alias_name, :organization_id)
      .each_with_object({}) { |(name, id), h| h[normalize_alias(name)] = id }
  end

  def build_v1_to_v2_doc_lookup(db)
    map = {}
    db.execute("SELECT id, doc_url FROM documents") do |row|
      v2 = Warehouse::KpiDocument.where(doc_url: row["doc_url"]).pluck(:id).first
      map[row["id"]] = v2 if v2
    end
    map
  end

  def normalize_alias(str)
    return nil if str.blank?
    str.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def parameterize(str)
    str.to_s.unicode_normalize(:nfkc).downcase
       .gsub(/[^a-z0-9]+/, "-")
       .gsub(/(^-+|-+$)/, "")
       .slice(0, 200)
  end

  def published_at_from_v1(row)
    # v1 documents don't have published_at. Defer PDF metadata extraction to a follow-up
    # task (`kpis:backfill_published_at`). For now, use the document's fiscal year as a
    # weak signal: Jan 1 of the year. Mark as discovered_at_fallback so the view orders
    # PDF-metadata-sourced rows higher.
    return Date.parse(row["discovered_at"]) if row["discovered_at"].present?
    Date.new(row["year"], 1, 1) if row["year"]
  rescue ArgumentError
    nil
  end

  def published_at_source_from_v1(_row)
    "discovered_at_fallback"
  end
end
