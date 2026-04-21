module HasLocalizedMarkdown
  extend ActiveSupport::Concern

  BLOB_PATH_PATTERN = %r{/rails/active_storage/blobs/(?:redirect/|proxy/)?(?<signed_id>[^/\s)]+)}

  included do
    has_many_attached :content_images
    after_save :attach_inline_markdown_blobs
  end

  class_methods do
    def has_localized_markdown(name)
      I18n.available_locales.each do |locale|
        column = :"#{name}_md_#{locale}"

        # Write: accept either raw markdown or HTML (auto-converted via
        # Markdown::HtmlConverter, which also pulls external images into AS).
        define_method(:"#{name}_#{locale}=") do |value|
          markdown = looks_like_html?(value) ? Markdown::HtmlConverter.call(value, record: self) : value.to_s
          write_attribute(column, markdown.presence)
        end

        # Read: raw markdown.
        define_method(:"#{name}_#{locale}") do
          read_attribute(column)
        end

        # Rendered HTML, per locale.
        define_method(:"#{name}_html_#{locale}") do
          Markdown::Renderer.call(read_attribute(column))
        end
      end

      # Locale-aware reader with fallback to English.
      define_method(name) do
        value = public_send(:"#{name}_#{I18n.locale}")
        value = public_send(:"#{name}_en") if value.blank? && I18n.locale != :en
        value
      end

      # Locale-aware writer.
      define_method(:"#{name}=") do |value|
        public_send(:"#{name}_#{I18n.locale}=", value)
      end

      # Locale-aware rendered HTML.
      define_method(:"#{name}_html") do
        markdown = public_send(name)
        Markdown::Renderer.call(markdown)
      end
    end
  end

  private

  def looks_like_html?(value)
    return false if value.blank?
    value.to_s.match?(/<[a-z][\s\S]*>/i)
  end

  # After save, ensure any ActiveStorage blob referenced in our markdown is
  # actually attached to this record, so Rails's unattached-blob GC won't purge
  # images that were uploaded inline via the editor.
  def attach_inline_markdown_blobs
    signed_ids = collect_signed_blob_ids
    return if signed_ids.empty?

    already_attached = content_images.blobs.pluck(:id).to_set
    blobs_to_attach  = signed_ids.filter_map { |sid| ActiveStorage::Blob.find_signed(sid) }
                                 .reject { |blob| already_attached.include?(blob.id) }

    content_images.attach(blobs_to_attach) if blobs_to_attach.any?
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    # skip bogus signed ids
  end

  def collect_signed_blob_ids
    self.class.markdown_fields.flat_map do |field|
      I18n.available_locales.map do |locale|
        read_attribute(:"#{field}_md_#{locale}")
      end
    end.compact.flat_map { |md| md.scan(BLOB_PATH_PATTERN).flatten }.uniq
  end
end
