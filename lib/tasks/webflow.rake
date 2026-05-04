namespace :webflow do
  desc "Resync seo_image for existing Build Canada memos (publication: nil) only"
  task resync_memo_seo_images: :environment do
    result = WebflowSyncService.new.resync_memo_seo_images!
    puts "Resync complete: #{result.except(:errors).inspect}"
    if result[:errors].any?
      puts "\nErrors:"
      result[:errors].each { |e| puts "  - #{e}" }
    end
  end
end
