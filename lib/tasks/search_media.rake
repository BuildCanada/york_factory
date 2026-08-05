require "set"

namespace :search do
  namespace :media do
    desc "Idempotently provision the configured media RSS sources"
    task provision_feeds: :environment do
      sources = Search::Media::FeedCatalog.provision!
      puts "Provisioned #{sources.size} media feeds"
    end

    desc "Backfill new media articles evenly across configured RSS sources (default: 50)"
    task :backfill, [ :limit ] => :environment do |_task, args|
      limit = Integer(args[:limit].presence || 50)
      raise ArgumentError, "limit must be between 1 and 500" unless limit.between?(1, 500)

      sources = Search::Source.enabled
        .where(realm: "media", strategy: %w[rss atom])
        .order(:id)
        .to_a
      raise "No enabled media feeds are configured" if sources.empty?

      fetcher = Search::Media::FeedFetcher.new
      defuddler = Search::Media::DefuddlerClient.new
      queues = {}
      failures = []
      skipped = 0

      sources.each do |source|
        result = fetcher.call(
          url: source.url,
          allow_http: source.configuration.to_h["allow_http"] == true
        )
        queues[source.id] = result.entries.dup
        puts "Fetched #{result.entries.length} entries from #{source.name}"
      rescue => error
        queues[source.id] = []
        failures << "#{source.name} feed: #{error.class}: #{error.message}"
        warn "Could not fetch #{source.name}: #{error.message}"
      end

      imported_ids = Set.new
      provider_counts = Hash.new(0)

      while imported_ids.length < limit
        made_progress = false

        sources.each do |source|
          break if imported_ids.length >= limit

          entry = queues.fetch(source.id).shift
          next unless entry

          made_progress = true
          canonical_url = SafeUrl.canonicalize(entry.fetch("url"))
          external_key = SafeUrl.digest(canonical_url)
          existing = Search::MediaArticle.find_by(
            search_source_id: source.id,
            external_key:
          )
          if existing
            skipped += 1
            next
          end

          extraction = defuddler.convert(
            url: entry.fetch("url"),
            language: source.configuration.to_h["language"]
          )
          result = Search::MediaArticle.import!(source:, feed_entry: entry, extraction:)
          result.article.sync_to_search! if result.changed
          unless imported_ids.add?(result.article.id)
            skipped += 1
            next
          end

          provider = result.article.realm_data.fetch("publisher_name")
          provider_counts[provider] += 1
          puts "[#{imported_ids.length}/#{limit}] #{provider}: #{result.article.title}"
        rescue => error
          failures << "#{source.name} article: #{error.class}: #{error.message}"
          warn "Skipped article from #{source.name}: #{error.message}"
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
