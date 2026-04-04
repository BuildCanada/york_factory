namespace :webflow do
  desc "Re-sync all images from Webflow (purges existing attachments first)"
  task resync_images: :environment do
    service = WebflowSyncService.new
    models = {
      "TeamMember" => { attachment: :profile_photo, field: "profile-photo" },
      "Tool" => { attachment: :image, field: "image" },
      "Builder" => { attachment: :image, field: "image" },
      "Memo" => { attachment: :seo_image, field: "open-graph-image" }
    }

    models.each do |model_name, config|
      klass = model_name.constantize
      attachment_name = config[:attachment]
      count = 0

      klass.find_each do |record|
        next unless record.send(attachment_name).attached?

        record.send(attachment_name).purge
        count += 1
      end

      puts "Purged #{count} #{model_name} attachments"
    end

    puts "\nRunning full sync to re-download images..."
    result = service.sync!
    puts "Sync complete: #{result.to_h.except(:errors).inspect}"

    if result.errors.any?
      puts "\nErrors:"
      result.errors.each { |e| puts "  - #{e}" }
    end
  end
end
