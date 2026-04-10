require "rss"

class SubstackPost::Backfiller
  include DownloadsImages

  FEED_URL = "https://buildcanada.substack.com/feed"

  def self.call
    new.call
  end

  def call
    items = fetch_rss_items
    items.each { |item| create_post(item) }

    Rails.logger.info "[SubstackPost::Backfiller] processed #{items.size} posts"
  rescue => e
    Rails.logger.error "[SubstackPost::Backfiller] failed: #{e.message}"
  end

  private

  def fetch_rss_items
    response = HTTPX.get(FEED_URL)
    return [] unless response.status == 200

    feed = RSS::Parser.parse(response.body.to_s, false)
    return [] unless feed

    feed.items.map { |item| normalize_item(item) }
  end

  def normalize_item(item)
    {
      external_url: item.link,
      title: item.title,
      subtitle: extract_subtitle(item),
      body: item.content_encoded || item.description,
      author_name: item.respond_to?(:dc_creator) ? item.dc_creator : nil,
      image_url: extract_image(item),
      posted_at: item.pubDate || Time.current
    }
  end

  def create_post(item)
    post = SubstackPost.find_or_create_by!(external_url: item[:external_url]) do |p|
      p.title = item[:title]
      p.subtitle = item[:subtitle]
      p.body = item[:body]
      p.author_name = item[:author_name]
      p.image_url = item[:image_url]
      p.posted_at = item[:posted_at]
    end

    attach_image_from_url(post, :image, item[:image_url])
  end

  def extract_subtitle(item)
    return nil unless item.description

    text = item.description.gsub(/<[^>]*>/, "").strip
    text.truncate(200)
  end

  def extract_image(item)
    return nil unless item.respond_to?(:enclosure) && item.enclosure

    item.enclosure.url if item.enclosure.type&.start_with?("image/")
  rescue
    nil
  end
end
