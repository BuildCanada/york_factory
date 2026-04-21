module AdminMarkdownHelper
  ALLOWED_TAGS = (
    ActionView::Helpers::SanitizeHelper.sanitizer_vendor.safe_list_sanitizer.allowed_tags.to_a +
    %w[table thead tbody tfoot tr th td span figure figcaption]
  ).uniq.freeze

  ALLOWED_ATTRIBUTES = (
    ActionView::Helpers::SanitizeHelper.sanitizer_vendor.safe_list_sanitizer.allowed_attributes.to_a +
    %w[class id colspan rowspan]
  ).uniq.freeze

  def render_markdown(markdown)
    return "" if markdown.blank?
    rendered = Marksmith::Renderer.new(body: markdown).render
    sanitize(rendered, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
  end
end
