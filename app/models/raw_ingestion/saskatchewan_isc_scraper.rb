class RawIngestion::SaskatchewanIscScraper < ActiveRecord::AssociatedObject
  include CorporateNormalization
  include ProvincialScraping

  performs :scrape

  SEARCH_URL = "https://corporateregistry.isc.ca/CorpRegistrySearch"

  def scrape(search_names: nil)
    rows_processed = 0

    names = search_names || seed_names_for_province("SK")
    last_searched = get_scraping_progress("last_searched_index")&.to_i || 0

    names.each_with_index do |name, idx|
      next if idx < last_searched

      begin
        results = search_registry(name)
        records = results.map { |r| map_result(r) }.compact

        if records.any?
          now = Time.current
          batch_upsert!(records.map { |r| r.merge(created_at: now, updated_at: now) })
          rows_processed += records.size
        end

        save_scraping_progress("last_searched_index", idx)
      rescue => e
        Rails.logger.error "[SaskatchewanIscScraper] Error searching '#{name}': #{e.message}"
        save_scraping_progress("last_error", { name: name, error: e.message, at: Time.current.iso8601 })
      end
    end

    raw_ingestion.update!(status: :complete)
    Rails.logger.info "[SaskatchewanIscScraper] Processed #{rows_processed} SK corps for ingestion #{raw_ingestion.id}"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def search_registry(name)
    page = rate_limited_get(SEARCH_URL)
    form = page.forms.first
    return [] unless form

    search_field = form.fields.find { |f| f.name =~ /name|search|query|EntityName/i }
    return [] unless search_field

    search_field.value = name
    result_page = rate_limited_submit(form)

    parse_results(result_page)
  rescue Mechanize::Error, Net::OpenTimeout => e
    Rails.logger.warn "[SaskatchewanIscScraper] Search failed for '#{name}': #{e.message}"
    []
  end

  def parse_results(page)
    results = []

    page.search("table tr, .search-results tr").each do |row|
      cells = row.search("td")
      next if cells.size < 2

      name = cells[0]&.text&.strip
      number = cells[1]&.text&.strip
      status = cells[2]&.text&.strip

      next if name.blank? || number.blank?

      results << {
        name: name,
        registry_id: number.gsub(/\D/, ""),
        status: status
      }
    end

    results
  end

  def map_result(result)
    return nil if result[:registry_id].blank? || result[:name].blank?

    {
      jurisdiction: "sk",
      registry_id: result[:registry_id],
      legal_name: normalize_name(result[:name]),
      status: normalize_status(result[:status]),
      registered_office_province: "SK",
      source_system: "sk_isc",
      raw_ingestion_id: raw_ingestion.id
    }
  end

  def seed_names_for_province(province_code)
    BusinessEstablishment.where(province: province_code)
      .distinct.pluck(:business_name)
  end
end
