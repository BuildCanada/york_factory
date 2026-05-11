class NextjsRevalidator
  def self.bust_memo(slug)
    bust_tag("memo:#{slug}")
  end

  def self.bust_tag(tag)
    url    = ENV["NEXTJS_REVALIDATE_URL"]
    secret = ENV["NEXTJS_REVALIDATE_SECRET"]
    if url.blank? || secret.blank?
      Rails.logger.info "[NextjsRevalidator] skipped (NEXTJS_REVALIDATE_URL or _SECRET unset)"
      return
    end

    response = HTTPX.with(
      headers: {
        "Authorization" => "Bearer #{secret}",
        "Content-Type"  => "application/json"
      },
      timeout: { request_timeout: 5 }
    ).post(url, json: { tag: tag })

    unless (200..299).cover?(response.status)
      Rails.logger.warn "[NextjsRevalidator] HTTP #{response.status} busting #{tag}: #{response.body.to_s.first(200)}"
    end
  rescue => e
    Rails.logger.warn "[NextjsRevalidator] error busting #{tag}: #{e.class}: #{e.message}"
  end
end
