class RawIngestion::OrgbookBcNormalizer < ActiveRecord::AssociatedObject
  include CorporateNormalization

  performs :normalize

  BASE_URL = "https://orgbook.gov.bc.ca/api/v4/search/topic"
  PAGE_SIZE = 100

  def normalize(file_content: nil)
    records = []
    rows_processed = 0
    page = get_resume_page

    loop do
      response = fetch_page(page)
      results = response["results"] || []

      break if results.empty?

      results.each do |topic|
        record = map_topic(topic)
        next unless record

        records << record

        if records.size >= BATCH_SIZE
          batch_upsert!(records.dup.map { |r| r.merge(created_at: Time.current, updated_at: Time.current) })
          rows_processed += records.size
          records.clear
        end
      end

      save_progress(page)
      page += 1

      # Check if we've reached the end
      total = response["total"] || 0
      break if page * PAGE_SIZE >= total
    end

    if records.any?
      batch_upsert!(records.map { |r| r.merge(created_at: Time.current, updated_at: Time.current) })
      rows_processed += records.size
    end

    raw_ingestion.update!(status: :complete)
    Rails.logger.info "[OrgbookBcNormalizer] Processed #{rows_processed} BC corps for ingestion #{raw_ingestion.id}"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def fetch_page(page)
    url = "#{BASE_URL}?inactive=false&page=#{page}&page_size=#{PAGE_SIZE}"
    response = HTTPX.get(url)
    raise "OrgBook API error: HTTP #{response.status}" unless response.status == 200
    JSON.parse(response.body.to_s)
  end

  def map_topic(topic)
    names = topic["names"] || []
    primary_name = names.find { |n| n["type"] == "entity_name" } || names.first
    return nil unless primary_name

    source_id = topic["source_id"]
    return nil if source_id.blank?

    attributes = topic["attributes"] || []
    status = extract_attribute(attributes, "entity_status") || "Active"
    entity_type = extract_attribute(attributes, "entity_type")
    registration_date = extract_attribute(attributes, "registration_date")

    {
      jurisdiction: "bc",
      registry_id: source_id,
      legal_name: normalize_name(primary_name["text"]),
      status: normalize_bc_status(status),
      corporation_type: entity_type,
      incorporation_date: parse_date(registration_date),
      source_system: "orgbook_bc",
      raw_data: { topic_id: topic["id"] },
      raw_ingestion_id: raw_ingestion.id
    }
  end

  def extract_attribute(attributes, type)
    attr = attributes.find { |a| a["type"] == type }
    attr&.dig("value")
  end

  def normalize_bc_status(raw)
    case raw&.upcase
    when "ACT" then "Active"
    when "HIS" then "Historical"
    else raw
    end
  end

  def parse_date(text)
    return nil if text.blank?
    Date.parse(text)
  rescue Date::Error, ArgumentError
    nil
  end

  def get_resume_page
    raw_ingestion.scraping_progress&.dig("last_page")&.to_i&.+(1) || 1
  end

  def save_progress(page)
    progress = raw_ingestion.scraping_progress || {}
    progress["last_page"] = page
    raw_ingestion.update_column(:scraping_progress, progress)
  end
end
