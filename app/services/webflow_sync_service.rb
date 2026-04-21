class WebflowSyncService
  WEBFLOW_BASE = "https://api.webflow.com/v2"
  SITE_ID = "679d23fc682f2bf860558c9a"

  COLLECTIONS = {
    team: "679d23fc682f2bf860558cdc",
    memos: "679d23fc682f2bf860558cbe",
    posts: "684867541456a61e3e1bee47",
    tools: "6852f12a87c79118b6e0fafb",
    builders: "6887ed9d9b83c3d68c8119d2"
  }.freeze

  ROLE_MAP = {
    "c5ce55e9374acb9562bb43aaaf69770d" => "board",
    "944812afca5b56a3cd9c34898e384517" => "team",
    "20ca1242b5afbfc6d502e24b42052210" => "volunteer"
  }.freeze

  CATEGORY_MAP = {
    "0fe9e9965e36fb950b3aba560b333550" => "housing",
    "eaa280191195bdaf636392c584783eb2" => "industry",
    "455e48223a385017de9dfc47886a6bc8" => "government-transformation",
    "0e69a7ae596c2271c5d587fef1c9b476" => "digital-innovation",
    "97cd702c4cb08d4e69ec7c47c112cca5" => "nation-building",
    "00d3874c9fe83b07882574ee96600deb" => "immigration",
    "b0d18b2b2f3955ca24414b0ff7745c95" => "energy",
    "fb551c04c199ab7dd0d7aef0a211764c" => "finance",
    "f927f68ffa12d7053acac7f765ebc039" => "defence"
  }.freeze

  class SyncError < StandardError; end

  Result = Struct.new(:team_members, :memos, :posts, :tools, :builders, :errors, keyword_init: true)

  def initialize(api_token: nil)
    @api_token = api_token || Rails.application.credentials.dig(:webflow, :api_token)
    @errors = []
    @team_id_map = {} # webflow_id => TeamMember record
  end

  def sync!
    counts = { team_members: 0, memos: 0, posts: 0, tools: 0, builders: 0 }

    Rails.logger.info "[WebflowSync] Starting sync..."

    counts[:team_members] = sync_team_members
    counts[:memos] = sync_memos
    counts[:posts] = sync_posts
    counts[:tools] = sync_tools
    counts[:builders] = sync_builders

    Rails.logger.info "[WebflowSync] Complete: #{counts.inspect}"

    Result.new(**counts, errors: @errors)
  end

  private

  def sync_team_members
    items = fetch_all_items(COLLECTIONS[:team])
    synced = 0

    items.each do |item|
      fd = item["fieldData"]
      slug = fd["slug"]
      next if slug.blank?

      member = TeamMember.find_or_initialize_by(slug: slug)
      role_hash = fd["role"].to_s
      role = ROLE_MAP[role_hash] || "team"

      member.assign_attributes(
        name: fd["name"],
        role: role,
        title_en: fd["title"].to_s,
        linkedin_url: fd["linkedin"].to_s.presence,
        twitter_url: fd["twitter"].to_s.presence,
        position: fd["team-order"].to_i
      )
      member.published_at ||= Time.current

      attach_image(member, :profile_photo, fd.dig("profile-photo", "url"), fd["name"])

      if member.save
        @team_id_map[item["id"]] = member
        synced += 1
      else
        @errors << "TeamMember '#{fd["name"]}': #{member.errors.full_messages.join(", ")}"
      end
    rescue => e
      @errors << "TeamMember '#{fd&.dig("name")}': #{e.message}"
    end

    Rails.logger.info "[WebflowSync] Synced #{synced}/#{items.size} team members"
    synced
  end

  def sync_memos
    items = fetch_all_items(COLLECTIONS[:memos])
    synced = 0

    items.each do |item|
      fd = item["fieldData"]
      slug = fd["slug"]
      next if slug.blank?

      memo = Memo.find_or_initialize_by(slug: slug)
      category_hash = fd["category"].to_s
      category = CATEGORY_MAP[category_hash]

      # Resolve author relationships
      # Webflow reference fields may return a string ID or an array of IDs
      builder_id = Array(fd["builder"]).first
      co_builder_id = Array(fd["builder-2"]).first
      author = builder_id ? @team_id_map[builder_id] : nil
      co_author = co_builder_id ? @team_id_map[co_builder_id] : nil

      # Key messages
      key_messages = (1..4).filter_map { |i|
        msg = fd["key-message-#{i}"]
        { "message" => msg } if msg.present?
      }

      memo.assign_attributes(
        title_en: fd["name"].to_s,
        category: category,
        author: author,
        co_author: co_author,
        key_messages_en: key_messages.presence || [],
        twitter_embed: fd["twitter-embed"].to_s.presence,
        author_name: fd["builder-name"].to_s.presence,
        author_title: fd["builder-title"].to_s.presence,
        author_avatar: fd["builder-avatar"].to_s.presence
      )
      # HasLocalizedMarkdown setter auto-detects HTML and converts to markdown,
      # downloading any inline images into ActiveStorage.
      memo.body_en = fd["body"].to_s if fd["body"].present?
      memo.appendix_en = fd["appendix"].to_s if fd["appendix"].present?
      memo.supporters_en = fd["supporters"].to_s if fd["supporters"].present?
      memo.published_at ||= Time.zone.parse(item["createdOn"]) rescue Time.current

      attach_image(memo, :seo_image, fd.dig("open-graph-image", "url"))

      if memo.save
        synced += 1
      else
        @errors << "Memo '#{fd["name"]}': #{memo.errors.full_messages.join(", ")}"
      end
    rescue => e
      @errors << "Memo '#{fd&.dig("name")}': #{e.message}"
    end

    Rails.logger.info "[WebflowSync] Synced #{synced}/#{items.size} memos"
    synced
  end

  def sync_posts
    items = fetch_all_items(COLLECTIONS[:posts])
    synced = 0

    items.each do |item|
      fd = item["fieldData"]
      slug = fd["slug"]
      next if slug.blank?

      post = Post.find_or_initialize_by(slug: slug)
      post.assign_attributes(
        title_en: fd["name"].to_s,
        summary_en: fd["post-summary"].to_s,
        hidden: fd["hidden"] == true
      )
      post.body_en = fd["post-body"].to_s if fd["post-body"].present?
      post.published_at ||= Time.current

      if post.save
        synced += 1
      else
        @errors << "Post '#{fd["name"]}': #{post.errors.full_messages.join(", ")}"
      end
    rescue => e
      @errors << "Post '#{fd&.dig("name")}': #{e.message}"
    end

    Rails.logger.info "[WebflowSync] Synced #{synced}/#{items.size} posts"
    synced
  end

  def sync_tools
    items = fetch_all_items(COLLECTIONS[:tools])
    synced = 0

    items.each do |item|
      fd = item["fieldData"]
      slug = fd["slug"]
      next if slug.blank?

      tool = Tool.find_or_initialize_by(slug: slug)
      tool.assign_attributes(
        title_en: fd["name"].to_s,
        url: fd["url"].to_s.presence
      )
      tool.description_en = fd["description"].to_s if fd["description"].present?
      tool.published_at ||= Time.current

      attach_image(tool, :image, fd.dig("image", "url"), fd["name"])

      if tool.save
        synced += 1
      else
        @errors << "Tool '#{fd["name"]}': #{tool.errors.full_messages.join(", ")}"
      end
    rescue => e
      @errors << "Tool '#{fd&.dig("name")}': #{e.message}"
    end

    Rails.logger.info "[WebflowSync] Synced #{synced}/#{items.size} tools"
    synced
  end

  def sync_builders
    items = fetch_all_items(COLLECTIONS[:builders])
    synced = 0

    items.each do |item|
      fd = item["fieldData"]
      slug = fd["slug"]
      next if slug.blank?

      builder = Builder.find_or_initialize_by(slug: slug)
      builder.assign_attributes(
        title_en: fd["name"].to_s,
        byline_en: fd["key-message-1"].to_s,
        quote_en: fd["quote"].to_s
      )
      builder.body_en = fd["body"].to_s if fd["body"].present?
      builder.author_en = fd["supporters"].to_s if fd["supporters"].present?
      builder.published_at ||= Time.current

      attach_image(builder, :image, fd.dig("image", "url"), fd["name"])

      if builder.save
        synced += 1
      else
        @errors << "Builder '#{fd["name"]}': #{builder.errors.full_messages.join(", ")}"
      end
    rescue => e
      @errors << "Builder '#{fd&.dig("name")}': #{e.message}"
    end

    Rails.logger.info "[WebflowSync] Synced #{synced}/#{items.size} builders"
    synced
  end

  # --- Webflow API ---

  def fetch_all_items(collection_id)
    items = []
    offset = 0

    loop do
      data = webflow_get("/collections/#{collection_id}/items?limit=100&offset=#{offset}")
      items.concat(data["items"] || [])
      offset += 100
      break if items.size >= data.dig("pagination", "total").to_i
    end

    items
  end

  def webflow_get(path)
    uri = URI("#{WEBFLOW_BASE}#{path}")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{@api_token}"
      http.request(req)
    end

    raise SyncError, "Webflow API #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  # --- Image attachment ---

  def attach_image(record, attachment_name, url, alt_text = nil)
    return if url.blank?
    return if record.send(attachment_name).attached?

    response = fetch_image(url)
    return unless response

    content_type = response["content-type"] || "image/png"
    uri = URI(url)
    filename = File.basename(uri.path).gsub("%20", "-")
    filename += image_extension(content_type) unless filename.include?(".")

    record.send(attachment_name).attach(
      io: StringIO.new(response.body),
      filename: filename,
      content_type: content_type
    )
  rescue => e
    @errors << "Image attach failed (#{url}): #{e.message}"
  end

  def fetch_image(url, redirect_limit = 5)
    return nil if redirect_limit == 0

    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(Net::HTTP::Get.new(uri))
    end

    case response
    when Net::HTTPSuccess
      response
    when Net::HTTPRedirection
      fetch_image(response["location"], redirect_limit - 1)
    end
  end

  def image_extension(content_type)
    case content_type
    when /webp/ then ".webp"
    when /png/ then ".png"
    else ".jpg"
    end
  end
end
