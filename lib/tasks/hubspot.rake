namespace :hubspot do
  desc "Backfill all subscribers into HubSpot via direct CRM sync (bypasses form workflows)"
  task backfill_subscribers: :environment do
    count = Subscriber.count
    puts "Enqueuing HubSpot sync jobs for #{count} subscribers (60/minute)..."

    Subscriber.backfill_hubspot_sync

    puts "Done. Jobs will drain over ~#{(count / 60.0).ceil} minutes."
  end
end
