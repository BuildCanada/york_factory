class Metrics::ScrapeZernioSocialMediaJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :default

  retry_on Metrics::ZernioClient::Error,
    wait: :polynomially_longer, attempts: 5

  def perform
    return Rails.logger.warn("[Zernio] API key is not configured") if api_key.blank?

    @scraper = scraper

    step :sync_accounts do
      @scraper.sync_accounts!
    end

    step :sync_posts, start: 1 do |step|
      loop do
        result = @scraper.sync_page!(page: step.cursor)
        Rails.logger.info("[Zernio] processed page #{step.cursor} (#{result[:processed]} posts)")
        break unless result[:next_page]

        step.advance!
      end
    end

    step :sync_account_daily_metrics, start: 0 do |step|
      Metrics::SocialMediaAccount.where(platform: Metrics::ZernioScraper::ACCOUNT_DAILY_PLATFORMS)
        .where(id: (step.cursor + 1)..).find_each do |account|
          @scraper.sync_account_daily_metrics!(account_id: account.id)
          step.advance! from: account.id
        end
    end

    step :sync_ad_accounts, start: 0 do |step|
      Metrics::SocialMediaAccount.where(ads_status: "connected").where(id: (step.cursor + 1)..).find_each do |account|
        @scraper.sync_ad_account!(account_id: account.id)
        step.advance! from: account.id
      end
    end

    step :sync_ad_campaigns, start: 1 do |step|
      sync_pages(step, :sync_ad_campaigns_page!, "campaigns")
    end

    step :sync_ads, start: 1 do |step|
      sync_pages(step, :sync_ads_page!, "ads")
    end

    sync_records(:sync_ad_account_analytics, Metrics::SocialMediaAdAccount, :sync_ad_account_analytics!)
    sync_records(:sync_ad_campaign_analytics, Metrics::SocialMediaAdCampaign, :sync_ad_campaign_analytics!)
    sync_records(:sync_ad_analytics, Metrics::SocialMediaAd, :sync_ad_analytics!)
  end

  private

  def sync_pages(step, method, label)
    loop do
      result = @scraper.public_send(method, page: step.cursor)
      Rails.logger.info("[Zernio] processed #{label} page #{step.cursor} (#{result[:processed]} records)")
      break unless result[:next_page]

      step.advance!
    end
  end

  def sync_records(name, model, method)
    step name, start: 0 do |step|
      model.where(id: (step.cursor + 1)..).find_each do |record|
        @scraper.public_send(method, id: record.id)
        step.advance! from: record.id
      end
    end
  end

  def scraper
    Metrics::ZernioScraper.new(
      client: Metrics::ZernioClient.new(api_key: api_key)
    )
  end

  def api_key
    ENV["ZERNIO_API_KEY"].presence || Rails.application.credentials.dig(:zernio, :api_key)
  end
end
