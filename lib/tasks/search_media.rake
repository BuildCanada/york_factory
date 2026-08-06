require "set"

namespace :search do
  namespace :media do
    desc "Idempotently create the initial media feeds"
    task provision_feeds: :environment do
      load Rails.root.join("db/seeds/media_feeds.rb")
      puts "Provisioned #{Warehouse::MediaFeed.count} media feeds"
    end

    desc "Backfill new media articles evenly across configured feeds (default: 50)"
    task :backfill, [ :limit ] => :environment do |_task, args|
      limit = Integer(args[:limit].presence || 50)
      raise ArgumentError, "limit must be between 1 and 500" unless limit.between?(1, 500)

      feeds = Warehouse::MediaFeed.enabled
        .order(:id)
        .to_a
      raise "No enabled media feeds are configured" if feeds.empty?

      fetcher = Search::Media::FeedFetcher.new
      defuddler = Search::Media::DefuddlerClient.new
      queues = {}
      failures = []
      skipped = 0

      feeds.each do |feed|
        result = fetcher.call(
          url: feed.url,
          allow_http: feed.allow_http?
        )
        queues[feed.id] = result.entries.dup
        puts "Fetched #{result.entries.length} entries from #{feed.name}"
      rescue => error
        queues[feed.id] = []
        failures << "#{feed.name} feed: #{error.class}: #{error.message}"
        warn "Could not fetch #{feed.name}: #{error.message}"
      end

      imported_ids = Set.new
      provider_counts = Hash.new(0)

      while imported_ids.length < limit
        made_progress = false

        feeds.each do |feed|
          break if imported_ids.length >= limit

          entry = queues.fetch(feed.id).shift
          next unless entry

          made_progress = true
          canonical_url = SafeUrl.canonicalize(entry.fetch("url"))
          external_key = SafeUrl.digest(canonical_url)
          existing = Warehouse::MediaArticle.find_by(
            search_media_feed_id: feed.id,
            external_key:
          )
          if existing
            skipped += 1
            next
          end

          extraction = defuddler.convert(
            url: entry.fetch("url"),
            language: feed.language
          )
          result = Warehouse::MediaArticle.import!(feed:, feed_entry: entry, extraction:)
          result.article.sync_to_search! if result.changed
          unless imported_ids.add?(result.article.id)
            skipped += 1
            next
          end

          provider = result.article.realm_data.fetch("publisher_name")
          provider_counts[provider] += 1
          puts "[#{imported_ids.length}/#{limit}] #{provider}: #{result.article.title}"
        rescue => error
          failures << "#{feed.name} article: #{error.class}: #{error.message}"
          warn "Skipped article from #{feed.name}: #{error.message}"
        end

        break unless made_progress
      end

      puts "Imported #{imported_ids.length} new articles; skipped #{skipped}; failures #{failures.length}"
      puts "Provider mix: #{provider_counts.sort.to_h.inspect}"
      failures.first(20).each { |failure| warn failure }
      raise "Only imported #{imported_ids.length} of #{limit} requested articles" if imported_ids.length < limit
    end
  end
end
