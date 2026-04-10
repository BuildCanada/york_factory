class SocialPost::TikTok::Backfiller
  API_BASE = "https://open.tiktokapis.com/v2"

  def self.call
    new.call
  end

  def call
    return unless access_token.present?

    videos = fetch_recent_videos
    videos.each { |video| create_post(video) }

    Rails.logger.info "[TikTok::Backfiller] processed #{videos.size} videos"
  rescue => e
    Rails.logger.error "[TikTok::Backfiller] failed: #{e.message}"
  end

  private

  def fetch_recent_videos
    fields = "id,title,video_description,cover_image_url,share_url,create_time"
    response = HTTPX.post(
      "#{API_BASE}/video/list/",
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Content-Type" => "application/json"
      },
      json: { max_count: 20, fields: fields.split(",") }
    )
    return [] unless response.status == 200

    body = JSON.parse(response.body.to_s)
    (body.dig("data", "videos") || []).map { |v| normalize_video(v) }
  end

  def normalize_video(video)
    {
      external_id: video["id"],
      title: video["title"],
      description: video["video_description"],
      image_url: video["cover_image_url"],
      url: video["share_url"],
      posted_at: Time.at(video["create_time"])
    }
  end

  def create_post(video)
    SocialPost::TikTok.find_or_create_by!(external_id: video[:external_id]) do |post|
      post.account_handle = "@build_canada"
      post.title = video[:title]
      post.body = video[:description]
      post.url = video[:url]
      post.image_url = video[:image_url]
      post.author_name = "Build Canada"
      post.posted_at = video[:posted_at]
      post.metadata = {}
    end
  end

  def access_token
    ENV["TIKTOK_ACCESS_TOKEN"]
  end
end
