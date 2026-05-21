class WebflowSyncService
  include Webflow::ImageAttachment

  COLLECTIONS = {
    memos: "679d23fc682f2bf860558cbe"
  }.freeze

  def initialize(api_token: nil)
    token = api_token || Rails.application.credentials.dig(:webflow, :api_token)
    @client = Webflow::Client.new(token)
    @errors = []
  end

  # One-off remediation: attach seo_image for Build Canada memos
  # that already exist in the CMS but never got one.
  # Skips memos not found locally and memos that already have an seo_image.
  def resync_memo_seo_images!
    Rails.logger.info "[WebflowSync] Resyncing SEO images for existing Build Canada memos..."
    items = @client.fetch_all_items(COLLECTIONS[:memos])
    updated = 0
    already_attached = 0
    missing = 0
    skipped = 0

    items.each do |item|
      next if item["isArchived"] == true
      fd = item["fieldData"]
      slug = fd["slug"]
      next if slug.blank?

      memo = Memo.find_by(slug: slug, publication: Memo::DEFAULT_PUBLICATION)
      if memo.nil?
        missing += 1
        next
      end

      if memo.seo_image.attached?
        already_attached += 1
        next
      end

      image_url = fd.dig("seo-image", "url") || fd.dig("open-graph-image", "url")
      if image_url.blank?
        skipped += 1
        next
      end

      attach_image(memo, :seo_image, image_url)
      updated += 1
    rescue => e
      @errors << "Memo SEO image '#{fd&.dig("name")}': #{e.message}"
    end

    Rails.logger.info "[WebflowSync] Attached #{updated} seo_images " \
                      "(#{already_attached} already had one, #{missing} not in CMS, " \
                      "#{skipped} no Webflow image, #{@errors.size} errors)"
    { updated: updated, already_attached: already_attached, missing: missing, skipped: skipped, errors: @errors }
  end
end
