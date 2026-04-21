require "net/http"
require "uri"

module Markdown
  # Walks an HTML fragment, pulls any <img> whose src points somewhere other than
  # our own ActiveStorage, downloads it, attaches it to `record.content_images`,
  # and rewrites the src to the ActiveStorage blob path.
  #
  # Also unwraps ActionText attachments (<action-text-attachment sgid=...>) so
  # the resulting HTML is plain <img src="/rails/active_storage/...">, which
  # reverse_markdown can handle.
  class ImageIngestor
    include Rails.application.routes.url_helpers

    def self.call(html, record:)
      new(html, record).call
    end

    def initialize(html, record)
      @html = html.to_s
      @record = record
    end

    def call
      return @html if @html.blank?

      doc = Nokogiri::HTML.fragment(@html)

      unwrap_action_text_attachments(doc)
      doc.css("img").each { |img| rewrite_img(img) }

      doc.to_html
    end

    private

    # ActionText stores images as:
    #   <action-text-attachment sgid="..." content-type="image/png" url="https://..." filename="..." />
    # Replace each with a plain <img src="...as blob path..." alt="filename">.
    def unwrap_action_text_attachments(doc)
      doc.css("action-text-attachment").each do |node|
        sgid = node["sgid"]
        next if sgid.blank?

        blob = ActiveStorage::Blob.find_signed(sgid)
        next unless blob

        img = Nokogiri::XML::Node.new("img", doc)
        img["src"] = blob_url(blob)
        img["alt"] = node["filename"].to_s
        node.replace(img)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        node.remove
      end
    end

    def rewrite_img(img)
      src = img["src"].to_s.strip
      return if src.blank?
      return if already_local_blob?(src)

      blob = download_to_blob(src, alt: img["alt"])
      return unless blob

      attach_to_record(blob)
      img["src"] = blob_url(blob)
      img["alt"] ||= blob.filename.to_s
    end

    def already_local_blob?(src)
      src.include?("/rails/active_storage/") || src.start_with?("data:")
    end

    def blob_url(blob)
      rails_blob_url(blob)
    end

    def download_to_blob(url, alt: nil)
      response = fetch(url)
      return nil unless response

      content_type = (response["content-type"] || "image/png").split(";").first.strip
      filename     = filename_for(url, alt: alt, content_type: content_type)

      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(response.body),
        filename: filename,
        content_type: content_type
      )
    rescue => e
      Rails.logger.warn("[Markdown::ImageIngestor] Failed to download #{url}: #{e.message}")
      nil
    end

    def fetch(url, redirects_left: 5)
      return nil if redirects_left <= 0

      uri = URI(url)
      return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(Net::HTTP::Get.new(uri))
      end

      case response
      when Net::HTTPSuccess
        response
      when Net::HTTPRedirection
        fetch(response["location"], redirects_left: redirects_left - 1)
      end
    end

    def filename_for(url, alt:, content_type:)
      basename = File.basename(URI(url).path).presence || alt.to_s.parameterize.presence || "image"
      basename = basename.gsub("%20", "-")
      basename += extension_for(content_type) unless basename.include?(".")
      basename
    rescue URI::InvalidURIError
      "image#{extension_for(content_type)}"
    end

    def extension_for(content_type)
      case content_type
      when /webp/ then ".webp"
      when /png/  then ".png"
      when /gif/  then ".gif"
      when /svg/  then ".svg"
      else ".jpg"
      end
    end

    def attach_to_record(blob)
      return unless @record.respond_to?(:content_images)
      @record.content_images.attach(blob)
    end
  end
end
