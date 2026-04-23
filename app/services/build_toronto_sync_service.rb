class BuildTorontoSyncService
  include Webflow::ImageAttachment

  PUBLICATION = "build_toronto"
  MEMO_COLLECTION_NAMES = [ "Memos", "Memo" ].freeze
  BUILDER_COLLECTION_NAMES = [ "Builders", "Builder", "Team", "Team Members" ].freeze
  SITE_KEYWORDS = %w[toronto].freeze

  SyncError = Webflow::Client::Error

  Result = Struct.new(:memos, :errors, keyword_init: true)

  def initialize(api_token: nil, client: nil)
    @client = client || begin
      token = api_token || Rails.application.credentials.dig(:webflow, :build_toronto, :api_token)
      raise SyncError, "Missing build_toronto Webflow token" if token.blank?
      Webflow::Client.new(token)
    end
    @errors = []
  end

  def sync!
    Rails.logger.info "[BuildTorontoSync] Starting sync..."
    site_id             = discover_site_id
    collections         = list_collections(site_id)
    builders_collection = find_collection(collections, BUILDER_COLLECTION_NAMES)
    memos_collection    = find_collection(collections, MEMO_COLLECTION_NAMES)
    raise SyncError, "No memo-like collection found on site #{site_id}" unless memos_collection

    @builder_id_map = builders_collection ? sync_builders(builders_collection["id"]) : {}
    synced_memos    = sync_memos(memos_collection["id"])
    Rails.logger.info "[BuildTorontoSync] Complete: #{@builder_id_map.size} builders, #{synced_memos} memos, #{@errors.size} errors"
    Result.new(memos: synced_memos, errors: @errors)
  end

  private

  def discover_site_id
    sites = @client.get("/sites").fetch("sites", [])
    raise SyncError, "Token has access to no sites" if sites.empty?
    site = sites.find { |s|
      haystack = "#{s["displayName"]} #{s["shortName"]}".downcase
      SITE_KEYWORDS.any? { |kw| haystack.include?(kw) }
    } || sites.first
    site["id"]
  end

  def list_collections(site_id)
    @client.get("/sites/#{site_id}/collections").fetch("collections", [])
  end

  def find_collection(collections, names)
    collections.find { |c|
      names.include?(c["displayName"]) ||
        names.map(&:downcase).include?(c["slug"].to_s.downcase)
    }
  end

  def sync_builders(collection_id)
    items = @client.fetch_all_items(collection_id)
    id_map = {}

    items.each do |item|
      fd = item["fieldData"]
      name = fd["name"].to_s
      next if name.blank?

      member = TeamMember.where(role: "memo_author").find_by(name: name) ||
               TeamMember.new(name: name, role: "memo_author")

      member.assign_attributes(
        title_en: fd["title"].to_s,
        linkedin_url: fd["linkedin"].to_s.presence,
        twitter_url: fd["twitter"].to_s.presence
      )
      member.published_at ||= Time.current

      attach_image(member, :profile_photo, fd.dig("profile-photo", "url"), name)

      if member.save
        id_map[item["id"]] = member
      else
        @errors << "Builder '#{name}': #{member.errors.full_messages.join(", ")}"
      end
    rescue => e
      @errors << "Builder '#{fd&.dig("name")}': #{e.message}"
    end

    Rails.logger.info "[BuildTorontoSync] Synced #{id_map.size}/#{items.size} builders"
    id_map
  end

  def sync_memos(collection_id)
    items = @client.fetch_all_items(collection_id)
    synced = 0

    items.each do |item|
      fd = item["fieldData"]
      slug = fd["slug"]
      next if slug.blank?

      memo = Memo.find_or_initialize_by(slug: slug, publication: PUBLICATION)

      key_messages = (1..4).filter_map { |i|
        msg = fd["key-message-#{i}"]
        { "message" => msg } if msg.present?
      }

      builder_ref = Array(fd["builder"]).first
      author = builder_ref ? @builder_id_map[builder_ref] : nil

      memo.assign_attributes(
        publication: PUBLICATION,
        title_en: fd["name"].to_s,
        author: author,
        key_messages_en: key_messages.presence || [],
        twitter_embed: fd["twitter-embed"].to_s.presence
      )
      memo.body_en = fd["body"].to_s if fd["body"].present?
      memo.appendix_en = fd["appendix"].to_s if fd["appendix"].present?
      memo.supporters_en = fd["supporters"].to_s if fd["supporters"].present?
      memo.published_at ||= (Time.zone.parse(item["createdOn"].to_s) rescue Time.current)

      attach_image(memo, :seo_image, fd.dig("open-graph-image", "url") || fd.dig("seo-image", "url"))

      if memo.save
        synced += 1
      else
        @errors << "Memo '#{fd["name"]}': #{memo.errors.full_messages.join(", ")}"
      end
    rescue => e
      @errors << "Memo '#{fd&.dig("name")}': #{e.message}"
    end

    Rails.logger.info "[BuildTorontoSync] Synced #{synced}/#{items.size} memos"
    synced
  end
end
