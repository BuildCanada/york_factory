module DownloadsImages
  private

  def attach_image_from_url(record, attachment_name, url)
    return unless url.present?
    return if record.public_send(attachment_name).attached?

    response = HTTPX.get(url)
    return unless response.status == 200

    content_type = response.headers["content-type"]&.split(";")&.first || "image/jpeg"
    extension = content_type.split("/").last.sub("jpeg", "jpg")
    filename = "#{record.class.name.parameterize}-#{record.id}.#{extension}"

    record.public_send(attachment_name).attach(
      io: StringIO.new(response.body.to_s),
      filename: filename,
      content_type: content_type
    )
  rescue => e
    Rails.logger.warn "[DownloadsImages] Failed to attach #{url}: #{e.message}"
  end
end
