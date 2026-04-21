module Markdown
  class Renderer
    # Input is trusted (admin-authored or Webflow-sourced) so raw HTML is
    # preserved — embeds like <iframe>, <blockquote class="twitter-tweet">, etc.
    # must render through.
    OPTIONS = {
      parse: { smart: true },
      render: { unsafe: true, hardbreaks: false },
      extension: { table: true, autolink: true, strikethrough: true, footnotes: true, tagfilter: false }
    }.freeze

    def self.call(markdown)
      return "" if markdown.blank?
      Commonmarker.to_html(markdown, options: OPTIONS).to_s
    end
  end
end
