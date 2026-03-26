require "json"

# Webflow export category hash -> our enum values
WEBFLOW_CATEGORY_MAP = {
  "97cd702c4cb08d4e69ec7c47c112cca5" => "nation-building",
  "0e69a7ae596c2271c5d587fef1c9b476" => "digital-innovation",
  "0fe9e9965e36fb950b3aba560b333550" => "housing",
  "455e48223a385017de9dfc47886a6bc8" => "government-transformation",
  "00d3874c9fe83b07882574ee96600deb" => "immigration",
  "fb551c04c199ab7dd0d7aef0a211764c" => "finance",
  "b0d18b2b2f3955ca24414b0ff7745c95" => "energy",
  "eaa280191195bdaf636392c584783eb2" => "industry",
  "f927f68ffa12d7053acac7f765ebc039" => "defence"
}.freeze

# Webflow export role hash -> our enum values
WEBFLOW_ROLE_MAP = {
  "944812afca5b56a3cd9c34898e384517" => "team",
  "c5ce55e9374acb9562bb43aaaf69770d" => "board",
  "20ca1242b5afbfc6d502e24b42052210" => "advisor"
}.freeze

WEBFLOW_EXPORT_PATH = File.expand_path("~/dev/BuildCanada/website/scripts/webflow-export.json")

namespace :cms do
  desc "Seed CMS content from Webflow export (team, memos, posts, builders, tools)"
  task seed: :environment do
    unless File.exist?(WEBFLOW_EXPORT_PATH)
      abort "Webflow export not found at #{WEBFLOW_EXPORT_PATH}"
    end

    data = JSON.parse(File.read(WEBFLOW_EXPORT_PATH))

    records_to_translate = []

    # -----------------------------------------------------------------------
    # 1. Team Members
    # -----------------------------------------------------------------------
    puts "\n=== Importing Team Members ==="
    webflow_id_to_team_member = {}

    data["team"].each do |item|
      fd = item["fieldData"]
      next if fd["name"].blank?

      role = WEBFLOW_ROLE_MAP[fd["role"]]
      # Members without a role hash but with a team-order are volunteers
      role ||= "volunteer" if fd["team-order"].present?

      member = TeamMember.find_or_initialize_by(slug: fd["slug"].presence || fd["name"].parameterize)

      member.assign_attributes(
        name:          fd["name"].strip,
        title_en:      fd["title"].presence,
        role:          role,
        twitter_url:   fd["twitter"].presence,
        linkedin_url:  fd["linkedin"].presence,
        position:      fd["team-order"].to_i
      )

      if member.save
        webflow_id_to_team_member[item["id"]] = member
        print "."
      else
        puts "\n  SKIP #{fd['name']}: #{member.errors.full_messages.join(', ')}"
      end
    end

    puts "\n  Imported: #{webflow_id_to_team_member.size} team members"
    puts "  Total in DB: #{TeamMember.count}"

    # -----------------------------------------------------------------------
    # 2. Memos
    # -----------------------------------------------------------------------
    puts "\n=== Importing Memos ==="
    memo_count = 0

    data["memos"].each do |item|
      fd = item["fieldData"]
      next if fd["slug"].blank?

      author    = webflow_id_to_team_member[fd["builder"]]
      co_author = webflow_id_to_team_member[fd["builder-2"]]

      key_messages = [
        fd["key-message-1"],
        fd["key-message-2"],
        fd["key-message-3"],
        fd["key-message-4"]
      ].compact.reject(&:blank?)

      category = WEBFLOW_CATEGORY_MAP[fd["category"]]

      memo = Memo.find_or_initialize_by(slug: fd["slug"])

      memo.assign_attributes(
        title_en:        fd["name"].presence,
        description_en:  nil, # Webflow doesn't have a separate description
        key_messages_en: key_messages,
        category:        category,
        author:          author,
        co_author:       co_author,
        twitter_embed:   fd["twitter-embed"].presence,
        published_at:    item["lastPublished"].presence&.then { |d| Time.parse(d) rescue nil }
      )

      # Rich text fields via ActionText
      memo.supporters_en = fd["supporters"].presence if fd["supporters"].present?
      memo.body_en = fd["body"].presence if fd["body"].present?
      memo.appendix_en = fd["appendix"].presence if fd["appendix"].present?

      if memo.save
        memo_count += 1
        records_to_translate << memo
        print "."
      else
        puts "\n  SKIP #{fd['slug']}: #{memo.errors.full_messages.join(', ')}"
      end
    end

    puts "\n  Imported: #{memo_count} memos"
    puts "  Total in DB: #{Memo.count}"

    # -----------------------------------------------------------------------
    # 3. Posts
    # -----------------------------------------------------------------------
    puts "\n=== Importing Posts ==="
    post_count = 0

    data["posts"].each do |item|
      fd = item["fieldData"]
      next if fd["slug"].blank?

      post = Post.find_or_initialize_by(slug: fd["slug"])

      post.assign_attributes(
        title_en:   fd["name"].presence,
        summary_en: fd["post-summary"].presence,
        hidden:     fd["hidden"] == true,
        published_at: item["lastPublished"].presence&.then { |d| Time.parse(d) rescue nil }
      )

      post.body_en = fd["post-body"].presence if fd["post-body"].present?

      if post.save
        post_count += 1
        records_to_translate << post
        print "."
      else
        puts "\n  SKIP #{fd['slug']}: #{post.errors.full_messages.join(', ')}"
      end
    end

    puts "\n  Imported: #{post_count} posts"
    puts "  Total in DB: #{Post.count}"

    # -----------------------------------------------------------------------
    # 4. Builders
    # -----------------------------------------------------------------------
    puts "\n=== Importing Builders ==="
    builder_count = 0

    data["builders"].each do |item|
      fd = item["fieldData"]
      next if fd["slug"].blank?

      builder = Builder.find_or_initialize_by(slug: fd["slug"])

      builder.assign_attributes(
        title_en:  fd["name"].presence,
        quote_en:  fd["quote"].presence,
        byline_en: fd["key-message-1"].presence
      )

      builder.author_en = fd["supporters"].presence if fd["supporters"].present?
      builder.body_en = fd["body"].presence if fd["body"].present?

      if builder.save
        builder_count += 1
        records_to_translate << builder
        print "."
      else
        puts "\n  SKIP #{fd['slug']}: #{builder.errors.full_messages.join(', ')}"
      end
    end

    puts "\n  Imported: #{builder_count} builders"
    puts "  Total in DB: #{Builder.count}"

    # -----------------------------------------------------------------------
    # 5. Tools
    # -----------------------------------------------------------------------
    puts "\n=== Importing Tools ==="
    tool_count = 0

    data["tools"].each_with_index do |item, idx|
      fd = item["fieldData"]
      next if fd["slug"].blank?

      tool = Tool.find_or_initialize_by(slug: fd["slug"])

      tool.assign_attributes(
        title_en: fd["name"].presence,
        url:      fd["url"].presence,
        position: idx
      )

      tool.description_en = fd["description"].presence if fd["description"].present?

      if tool.save
        tool_count += 1
        records_to_translate << tool
        print "."
      else
        puts "\n  SKIP #{fd['slug']}: #{tool.errors.full_messages.join(', ')}"
      end
    end

    puts "\n  Imported: #{tool_count} tools"
    puts "  Total in DB: #{Tool.count}"

    # -----------------------------------------------------------------------
    # 6. Enqueue FR translation jobs
    # -----------------------------------------------------------------------
    puts "\n=== Enqueueing Translation Jobs ==="
    records_to_translate.each do |record|
      TranslateRecordJob.perform_later(record.class.name, record.id)
    end
    puts "  Enqueued: #{records_to_translate.size} translation jobs"

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    puts "\n=== Summary ==="
    puts "  Team Members: #{TeamMember.count}"
    puts "  Memos:        #{Memo.count}"
    puts "  Posts:        #{Post.count}"
    puts "  Builders:     #{Builder.count}"
    puts "  Tools:        #{Tool.count}"
    puts "  Translation jobs enqueued: #{records_to_translate.size}"
    puts "\nDone."
  end
end
