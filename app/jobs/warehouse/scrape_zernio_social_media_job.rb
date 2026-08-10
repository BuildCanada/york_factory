class Warehouse::ScrapeZernioSocialMediaJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :default

  retry_on Warehouse::SocialMedia::ZernioClient::Error,
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
  end

  private

  def scraper
    Warehouse::SocialMedia::ZernioScraper.new(
      client: Warehouse::SocialMedia::ZernioClient.new(api_key: api_key)
    )
  end

  def api_key
    ENV["ZERNIO_API_KEY"].presence || Rails.application.credentials.dig(:zernio, :api_key)
  end
end
