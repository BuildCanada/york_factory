class RawIngestion::EstimatesNormalizer < ActiveRecord::AssociatedObject
  performs :normalize

  # Estimates CSV columns (organization-summary.csv):
  #   Organization, Vote, Description,
  #   2023-24 Expenditures, 2024-25 Main Estimates,
  #   2024-25 Estimates To Date, 2025-26 Main Estimates
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

  def normalize(csv_content:)
    rows_processed = 0
    rows_skipped = 0
    resolver = Organization.new.entity_resolver

    # Force UTF-8 and strip BOM from government CSVs
    clean_content = csv_content.dup.force_encoding("UTF-8").scrub("")
    bom = +"\xEF\xBB\xBF"
    bom.force_encoding("UTF-8")
    clean_content.sub!(bom, "")

    # Detect fiscal year columns and document type from headers
    csv = CSV.parse(clean_content, headers: true, liberal_parsing: true)
    fiscal_year_columns = detect_fiscal_year_columns(csv.headers)

    csv.each do |row|
      org_name = row["Organization"]&.strip
      next if org_name.blank?

      begin
        result = resolver.resolve(name: org_name, raw_ingestion: raw_ingestion)

        if result.organization.nil?
          rows_skipped += 1
          Rails.logger.warn "[EstimatesNormalizer] Could not resolve org: #{org_name}"
          next
        end

        vote_raw = row["Vote"]&.strip
        vote_type = parse_vote_type(vote_raw)
        vote_number = vote_raw&.gsub(/\s+/, "")

        fiscal_year_columns.each do |col_name, fiscal_year, doc_type|
          amount = parse_amount(row[col_name])
          next if amount.nil?

          FiscalAuthority.find_or_initialize_by(
            organization: result.organization,
            fiscal_year: fiscal_year,
            document_type: doc_type,
            vote_number: vote_number
          ).tap do |fa|
            fa.vote_type = vote_type
            fa.description = row["Description"]&.strip
            fa.amount = amount
            fa.raw_ingestion = raw_ingestion
            fa.lineage_entry = result.lineage_entry
            fa.save!
          end

          rows_processed += 1
        end
      rescue => e
        rows_skipped += 1
        Rails.logger.error "[EstimatesNormalizer] Error on row #{org_name}: #{e.message}"

        LineageEntry.create!(
          raw_ingestion: raw_ingestion,
          source_field: "row",
          source_value: org_name,
          transformation_type: :skipped,
          confidence: 0
        )
      end
    end

    status = rows_skipped > 0 ? :partial : :complete
    raw_ingestion.update!(status: status)

    Rails.logger.info "[EstimatesNormalizer] Processed #{rows_processed} records, skipped #{rows_skipped} for ingestion #{raw_ingestion.id}"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def detect_fiscal_year_columns(headers)
    # Extract fiscal year and document type from column headers
    # e.g., "2025-26 Main Estimates" → ["2025-26", "main"]
    # e.g., "2024-25 Estimates To Date" → ["2024-25", "main"] (consolidated)
    # e.g., "2023-24 Expenditures" → skip (these are actuals, not estimates)
    results = []

    headers.each do |header|
      next unless header

      if header.match?(/\d{4}-\d{2}\s+Main Estimates/i)
        fiscal_year = header.match(/(\d{4}-\d{2})/)[1]
        results << [header, fiscal_year, "main"]
      elsif header.match?(/\d{4}-\d{2}\s+Supplementary.*?A/i)
        fiscal_year = header.match(/(\d{4}-\d{2})/)[1]
        results << [header, fiscal_year, "supp_a"]
      elsif header.match?(/\d{4}-\d{2}\s+Supplementary.*?B/i)
        fiscal_year = header.match(/(\d{4}-\d{2})/)[1]
        results << [header, fiscal_year, "supp_b"]
      elsif header.match?(/\d{4}-\d{2}\s+Supplementary.*?C/i)
        fiscal_year = header.match(/(\d{4}-\d{2})/)[1]
        results << [header, fiscal_year, "supp_c"]
      end
    end

    # Default: use the last Main Estimates column if found
    if results.empty?
      # Fallback: look for any column with a fiscal year pattern
      headers.each do |header|
        next unless header&.match?(/\d{4}-\d{2}/)
        next if header.match?(/Expenditures/i) # Skip actuals

        fiscal_year = header.match(/(\d{4}-\d{2})/)[1]
        results << [header, fiscal_year, "main"]
      end
    end

    results
  end

  def parse_vote_type(vote_raw)
    return "statutory" if vote_raw.blank? || vote_raw.match?(/\AS\s*\z/i)
    cleaned = vote_raw.gsub(/\s+/, "")
    VOTE_TYPE_MAP.fetch(cleaned, "operating")
  end

  def parse_amount(value)
    return nil if value.blank?
    # Handle parentheses as negatives, strip formatting
    str = value.to_s.strip
    negative = str.match?(/^\(.*\)$/)
    cleaned = str.gsub(/[$,()"]/, "").strip
    return nil if cleaned.blank? || cleaned == "-"
    amount = cleaned.to_d
    negative ? -amount : amount
  end
end
