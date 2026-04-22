class SocialPost::X::Backfiller
  include DownloadsImages

  ACCOUNTS = %w[build_canada canada_spends].freeze
  API_BASE = "https://api.x.com/2"

  def self.call
    new.call
  end

  def call
    return unless bearer_token.present?

    ACCOUNTS.each { |handle| backfill_account(handle) }
  end

  private

  def backfill_account(handle)
    user_id = fetch_user_id(handle)
    return unless user_id

    tweets = fetch_tweets(user_id, handle)
    tweets.each do |tweet|
      create_post(handle, tweet)
    end

    Rails.logger.info "[X::Backfiller] @#{handle}: processed #{tweets.size} tweets"
  rescue => e
    Rails.logger.error "[X::Backfiller] @#{handle} failed: #{e.message}"
  end

  def fetch_user_id(handle)
    response = client.get("#{API_BASE}/users/by/username/#{handle}")
    return unless response.status == 200

    JSON.parse(response.body.to_s).dig("data", "id")
  end

  def fetch_tweets(user_id, handle)
    params = {
      "max_results" => "100",
      "exclude" => "replies,retweets",
      "tweet.fields" => "created_at,text,attachments,entities",
      "expansions" => "attachments.media_keys,author_id",
      "media.fields" => "url,preview_image_url,type",
      "user.fields" => "name,profile_image_url"
    }

    # Only fetch tweets newer than our latest
    latest = SocialPost::X.where(account_handle: "@#{handle}").order(posted_at: :desc).first
    params["since_id"] = latest.external_id if latest

    query = params.map { |k, v| "#{k}=#{v}" }.join("&")
    response = client.get("#{API_BASE}/users/#{user_id}/tweets?#{query}")
    return [] unless response.status == 200

    body = JSON.parse(response.body.to_s)
    tweets = body["data"] || []
    media_map = build_media_map(body.dig("includes", "media") || [])
    user_map = build_user_map(body.dig("includes", "users") || [])

    tweets.map { |t| normalize_tweet(t, media_map, user_map) }
  end

  def create_post(handle, tweet)
    post = SocialPost::X.find_or_create_by!(external_id: tweet[:external_id]) do |p|
      p.account_handle = "@#{handle}"
      p.title = nil
      p.body = tweet[:text]
      p.url = tweet[:url]
      p.image_url = tweet[:image_url]
      p.author_name = tweet[:author_name]
      p.author_avatar_url = tweet[:author_avatar_url]
      p.posted_at = tweet[:posted_at]
      p.metadata = tweet[:metadata] || {}
    end

    attach_image_from_url(post, :image, tweet[:image_url])
    attach_image_from_url(post, :avatar, tweet[:author_avatar_url])
  end

  def normalize_tweet(tweet, media_map, user_map)
    media_keys = tweet.dig("attachments", "media_keys") || []
    image = media_keys.filter_map { |k| media_map[k] }.first

    author = user_map[tweet["author_id"]] || {}

    {
      external_id: tweet["id"],
      text: tweet["text"],
      url: "https://x.com/i/status/#{tweet["id"]}",
      image_url: image,
      author_name: author[:name],
      author_avatar_url: author[:avatar],
      posted_at: Time.parse(tweet["created_at"]),
      metadata: {}
    }
  end

  def build_media_map(media)
    media.each_with_object({}) do |m, map|
      map[m["media_key"]] = m["url"] || m["preview_image_url"]
    end
  end

  def build_user_map(users)
    users.each_with_object({}) do |u, map|
      map[u["id"]] = { name: u["name"], avatar: u["profile_image_url"] }
    end
  end

  def bearer_token
    Rails.application.credentials.dig(:twitter, :bearer_token)
  end

  def client
    @client ||= HTTPX.plugin(:auth).bearer_auth(bearer_token)
  end
end
