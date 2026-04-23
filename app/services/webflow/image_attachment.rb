module Webflow
  module ImageAttachment
    def attach_image(record, attachment_name, url, _alt_text = nil)
      return if url.blank?
      return if record.send(attachment_name).attached?

      response = fetch_image(url)
      return unless response

      content_type = response["content-type"] || "image/png"
      uri = URI(url)
      filename = File.basename(uri.path).gsub("%20", "-")
      filename += image_extension(content_type) unless filename.include?(".")

      record.send(attachment_name).attach(
        io: StringIO.new(response.body),
        filename: filename,
        content_type: content_type
      )
    rescue => e
      @errors << "Image attach failed (#{url}): #{e.message}" if defined?(@errors) && @errors
    end

    def fetch_image(url, redirect_limit = 5)
      return nil if redirect_limit == 0

      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      case response
      when Net::HTTPSuccess
        response
      when Net::HTTPRedirection
        fetch_image(response["location"], redirect_limit - 1)
      end
    end

    def image_extension(content_type)
      case content_type
      when /webp/ then ".webp"
      when /png/ then ".png"
      else ".jpg"
      end
    end
  end
end
