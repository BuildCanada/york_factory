module Markdown
  # Converts inbound HTML (Webflow sync, admin paste, etc.) into markdown while
  # ensuring every referenced image is stored in ActiveStorage on the given
  # record.
  class HtmlConverter
    def self.call(html, record:)
      return "" if html.blank?

      rewritten = ImageIngestor.call(html, record: record)
      # `pass_through` preserves unknown tags (iframes, twitter blockquotes, etc.)
      # verbatim in the markdown output.
      ReverseMarkdown.convert(
        rewritten,
        unknown_tags: :pass_through,
        github_flavored: true
      ).to_s.strip
    end
  end
end
