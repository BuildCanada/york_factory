# Input HTML is trusted (admin-authored or synced from Webflow) so we preserve
# embed-style elements verbatim rather than letting reverse_markdown convert
# them away. Their content renders through Commonmarker (which has unsafe: true)
# when the stored markdown is rendered to HTML.

module PassThroughConverter
  def self.convert(node, _state = {})
    "\n\n#{node.to_html}\n\n"
  end
end

ReverseMarkdown::Converters.register :iframe, PassThroughConverter
ReverseMarkdown::Converters.register :video, PassThroughConverter
ReverseMarkdown::Converters.register :audio, PassThroughConverter
ReverseMarkdown::Converters.register :embed, PassThroughConverter
ReverseMarkdown::Converters.register :object, PassThroughConverter
ReverseMarkdown::Converters.register :script, PassThroughConverter
