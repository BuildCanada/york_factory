class RawIngestion::InfobaseLoader < ActiveRecord::AssociatedObject
  performs :load

  # InfoBase CSV columns:
  #   fy_ef, org_id, org_name, voted_or_statutory, description, authorities, expenditures
  #
  # Vote type mapping:
  #   1  → operating
  #   5  → capital
  #   10 → grants_contributions
  #   "S" → statutory

  VOTE_TYPE_MAP = {
    "1" => "operating",
    "5" => "capital",
    "10" => "grants_contributions"
  }.freeze

  def load(csv_content:)
    rows_processed = 0
    resolver = Organization.new.entity_resolver

    # Force UTF-8, strip BOM, and normalize quoting artifacts from government CSVs
    clean_content = csv_content.dup.force_encoding("UTF-8").scrub("")
    bom = +"\xEF\xBB\xBF"
    bom.force_encoding("UTF-8")
    clean_content.sub!(bom, "")

    ActiveRecord::Base.transaction do
      CSV.parse(clean_content, headers: true, liberal_parsing: true) do |row|
        org_id = row["org_id"].to_i
        org_name = row["org_name"]&.strip
        next if org_name.blank?

        result = resolver.resolve_by_infobase_id(
          org_id: org_id,
          org_name: org_name,
          raw_ingestion: raw_ingestion
        )

        vote_raw = row["voted_or_statutory"]&.strip
        vote_type = parse_vote_type(vote_raw)
        vote_number = vote_raw == "S" ? "S" : vote_raw

        FiscalExpenditure.find_or_initialize_by(
          organization: result.organization,
          fiscal_year: row["fy_ef"]&.strip,
          vote_number: vote_number
        ).tap do |fe|
          fe.vote_type = vote_type
          fe.description = row["description"]&.strip
          fe.pa_voted_ceiling = parse_amount(row["authorities"])
          fe.actual_expenditure = parse_amount(row["expenditures"])
          fe.raw_ingestion = raw_ingestion
          fe.lineage_entry = result.lineage_entry
          fe.save!
        end

        rows_processed += 1
      end

      raw_ingestion.update!(status: :complete)
    end

    Rails.logger.info "[InfobaseLoader] Processed #{rows_processed} rows for ingestion #{raw_ingestion.id}"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def parse_vote_type(vote_raw)
    return "statutory" if vote_raw == "S" || vote_raw&.match?(/\AS\z/i)
    VOTE_TYPE_MAP.fetch(vote_raw.to_s, "operating")
  end

  def parse_amount(value)
    return nil if value.blank?
    value.to_s.gsub(/[$,]/, "").to_d
  end
end
