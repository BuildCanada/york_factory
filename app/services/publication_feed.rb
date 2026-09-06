class PublicationFeed
  KINDS = %w[all memos posts polls].freeze
  LIMIT = 50

  def initialize(kind, include_polls: true)
    raise ArgumentError, "Unknown feed" unless KINDS.include?(kind)
    @kind = kind
    @include_polls = include_polls
  end

  def render
    items = records
    document = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.rss(version: "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom") do
        xml.channel do
          xml.title(@kind == "all" ? "Build Canada" : "Build Canada | #{@kind.capitalize}")
          xml.link(@kind == "all" ? PublicWebsite.url : "#{PublicWebsite.url}/#{@kind}")
          xml.description("The latest #{@kind == 'all' ? 'memos, posts and polls' : @kind} from Build Canada.")
          xml.language("en-ca")
          xml.ttl(1)
          xml["atom"].link(href: "#{PublicWebsite.url}/feeds/#{@kind}.xml", rel: "self", type: "application/rss+xml")
          xml.lastBuildDate(items.map(&:updated_at).compact.max.rfc2822) if items.any?
          items.each do |record|
            xml.item do
              xml.title(record.title_en)
              xml.link(article_url(record))
              xml.guid("urn:buildcanada:#{record.model_name.singular}:#{record.id}", isPermaLink: "false")
              xml.pubDate(record.published_at.rfc2822)
              xml.category(record.model_name.plural)
              xml.description(excerpt(record))
            end
          end
        end
      end
    end
    document.to_xml
  end

  private

  def records
    scopes = { "memos" => Memo.published, "posts" => Post.published.visible, "polls" => Poll.published }
    scopes.delete("polls") if @kind == "all" && !@include_polls
    selected = @kind == "all" ? scopes.values : [ scopes.fetch(@kind) ]
    selected.flat_map { |scope| scope.order(published_at: :desc, id: :desc).limit(LIMIT).to_a }
      .sort_by { |record| [ -record.published_at.to_f, record.model_name.name, -record.id ] }.first(LIMIT)
  end

  def article_url(record)
    section = record.is_a?(Memo) && record.publication == "build_toronto" ? "toronto/memos" : record.model_name.plural
    "#{PublicWebsite.url}/#{section}/#{ERB::Util.url_encode(record.slug)}"
  end

  def excerpt(record)
    return record.summary_en if record.is_a?(Post) && record.summary_en.present?
    html = Nokogiri::HTML.fragment(record.body_html_en)
    html.css("script, style, pre[lang='buildcanada-chart']").remove
    html.css("code.language-buildcanada-chart").each { |code| code.parent.remove }
    html.css("p, h1, h2, h3, h4, li, br").each { |node| node.add_next_sibling(Nokogiri::XML::Text.new(" ", html)) }
    html.text.squish.truncate(600)
  end
end
