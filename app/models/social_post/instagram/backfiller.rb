class SocialPost::Instagram::Backfiller
  include DownloadsImages

  GRAPH_API_BASE = "https://graph.instagram.com/v21.0"

  def self.call
    new.call
  end

  def call
    return unless access_token.present?

    media_items = fetch_recent_media
    media_items.each { |item| create_post(item) }

    Rails.logger.info "[Instagram::Backfiller] processed #{media_items.size} posts"
  rescue => e
    Rails.logger.error "[Instagram::Backfiller] failed: #{e.message}"
  end

  private

  def fetch_recent_media
    fields = "id,caption,media_type,media_url,thumbnail_url,permalink,timestamp,username"
    response = HTTPX.get("#{GRAPH_API_BASE}/me/media?fields=#{fields}&limit=100&access_token=#{access_token}")
    return [] unless response.status == 200

    body = JSON.parse(response.body.to_s)
    (body["data"] || []).map { |item| normalize_item(item) }
  end

  def normalize_item(item)
    {
      external_id: item["id"],
      media_type: item["media_type"],
      caption: item["caption"],
      image_url: item["media_type"] == "VIDEO" ? item["thumbnail_url"] : item["media_url"],
      url: item["permalink"],
      username: item["username"],
      posted_at: Time.parse(item["timestamp"])
    }
  end

  def create_post(item)
    klass = reel?(item) ? SocialPost::InstagramReel : SocialPost::Instagram

    post = klass.find_or_create_by!(external_id: item[:external_id]) do |p|
      p.account_handle = "@#{item[:username] || "build_canada"}"
      p.title = nil
      p.body = item[:caption]
      p.url = item[:url]
      p.image_url = item[:image_url]
      p.author_name = item[:username]
      p.posted_at = item[:posted_at]
      p.metadata = { media_type: item[:media_type] }
    end

    attach_image_from_url(post, :image, item[:image_url])
  end

  def reel?(item)
    item[:media_type] == "VIDEO" || (item[:url] && (item[:url].include?("/reel/") || item[:url].include?("/tv/")))
  end

  def access_token
    ENV["INSTAGRAM_ACCESS_TOKEN"]
  end
end
