class CorporateEntity::Enricher < ActiveRecord::AssociatedObject
  performs :enrich

  ISED_API_BASE = "https://ised-isde.canada.ca/cc/lgcy/api/v1"
  MAX_REQUESTS_PER_MINUTE = 50
  REQUEST_DELAY = 60.0 / MAX_REQUESTS_PER_MINUTE

  def enrich
    return unless corporate_entity.jurisdiction == "federal"
    return if corporate_entity.enriched?

    data = fetch_directors
    return if data.nil?

    create_directors(data)

    corporate_entity.update!(enriched: true, enriched_at: Time.current)
    Rails.logger.info "[Enricher] Enriched federal corp #{corporate_entity.registry_id}"
  rescue => e
    Rails.logger.error "[Enricher] Failed to enrich #{corporate_entity.registry_id}: #{e.message}"
    corporate_entity.update!(needs_review: true)
  end

  private

  def fetch_directors
    sleep(REQUEST_DELAY)

    url = "#{ISED_API_BASE}/corporations/#{corporate_entity.registry_id}/directors"
    response = HTTPX.get(url, headers: { "Accept" => "application/json" })

    return nil unless response.status == 200

    JSON.parse(response.body.to_s)
  rescue JSON::ParserError
    nil
  end

  def create_directors(data)
    directors = data["directors"] || data["data"] || []

    directors.each do |dir|
      full_name = dir["name"] || [dir["firstName"], dir["lastName"]].compact.join(" ")
      next if full_name.blank?

      director = CorporateDirector.find_or_create_by!(
        normalized_name: full_name.downcase.strip.gsub(/\s+/, " "),
        postal_code: dir["postalCode"]&.strip
      ) do |d|
        d.full_name = full_name.strip
        d.address = dir["address"]&.strip
        d.province = dir["province"]&.strip
        d.country = dir["country"]&.strip
        d.is_resident_canadian = dir["residentCanadian"]
      end

      DirectorAppointment.find_or_create_by!(
        corporate_entity: corporate_entity,
        corporate_director: director
      ) do |appt|
        appt.appointed_date = parse_date(dir["appointmentDate"])
        appt.ceased_date = parse_date(dir["ceasedDate"])
        appt.role = dir["role"] || "Director"
      end
    end
  end

  def parse_date(text)
    return nil if text.blank?
    Date.parse(text.to_s)
  rescue Date::Error, ArgumentError
    nil
  end
end
