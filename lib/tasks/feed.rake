namespace :feed do
  desc "Create feed entries for all published Memos, Posts, and Builders"
  task backfill_existing: :environment do
    count = 0

    [Memo, Post, Builder].each do |klass|
      klass.published.find_each do |record|
        next if record.feed_entry.present?

        record.create_feed_entry!(
          published_at: record.feed_published_at,
          featured: record.feed_featured?
        )
        count += 1
      end

      puts "#{klass.name}: #{klass.published.count} published, feed entries synced"
    end

    puts "Created #{count} new feed entries total"
  end

  desc "Run all social media backfillers once"
  task backfill_social: :environment do
    [
      SocialPost::X::Backfiller
    ].each do |backfiller|
      puts "Running #{backfiller.name}..."
      backfiller.call
    end

    puts "Social backfill complete. #{SocialPost.count} total social posts."
  end

  desc "Run Substack RSS backfiller once"
  task backfill_substack: :environment do
    puts "Running SubstackPost::Backfiller..."
    SubstackPost::Backfiller.call
    puts "Substack backfill complete. #{SubstackPost.count} total substack posts."
  end

  desc "Run all backfillers (social + substack)"
  task backfill_all: :environment do
    Rake::Task["feed:backfill_existing"].invoke
    Rake::Task["feed:backfill_social"].invoke
    Rake::Task["feed:backfill_substack"].invoke
    puts "All backfills complete. #{FeedEntry.count} total feed entries."
  end
end
