class NextjsRevalidator
  def self.bust_memo(slug)
    bust_tag("memo:#{slug}")
  end

  def self.bust_tag(tag)
    Rails.logger.tagged("NextjsRevalidator") do
      url    = ENV["NEXTJS_REVALIDATE_URL"]
      secret = ENV["NEXTJS_REVALIDATE_SECRET"]
      if url.blank? || secret.blank?
        Rails.logger.info "skipped (NEXTJS_REVALIDATE_URL or _SECRET unset)"
        return
      end

      HTTPX.with(
        headers: {
          "Authorization" => "Bearer #{secret}",
          "Content-Type"  => "application/json"
        },
        timeout: { request_timeout: 5 }
      ).post(url, json: { tag: tag }).raise_for_status
    rescue => e
      Rails.logger.warn "error busting #{tag}: #{e.class}: #{e.message}"
    end
  end
end
