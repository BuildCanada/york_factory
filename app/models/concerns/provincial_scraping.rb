module ProvincialScraping
  extend ActiveSupport::Concern

  REQUEST_DELAY = 2 # seconds between requests
  MAX_RETRIES = 3
  BACKOFF_BASE = 5 # seconds

  USER_AGENT = "YorkFactory/0.2 (buildcanada.com; government-accountability-research)"

  private

  def scraping_agent
    @scraping_agent ||= Mechanize.new.tap do |agent|
      agent.user_agent = USER_AGENT
      agent.open_timeout = 30
      agent.read_timeout = 30
    end
  end

  def rate_limited_get(url)
    retries = 0
    begin
      sleep(REQUEST_DELAY) if @last_request_at
      @last_request_at = Time.current
      scraping_agent.get(url)
    rescue Mechanize::ResponseCodeError => e
      retries += 1
      if retries <= MAX_RETRIES && (e.response_code == "429" || e.response_code == "503")
        sleep(BACKOFF_BASE ** retries)
        retry
      end
      raise
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      retries += 1
      if retries <= MAX_RETRIES
        sleep(BACKOFF_BASE ** retries)
        retry
      end
      raise
    end
  end

  def rate_limited_submit(form, button = nil)
    retries = 0
    begin
      sleep(REQUEST_DELAY) if @last_request_at
      @last_request_at = Time.current
      if button
        scraping_agent.submit(form, button)
      else
        scraping_agent.submit(form)
      end
    rescue Mechanize::ResponseCodeError => e
      retries += 1
      if retries <= MAX_RETRIES && (e.response_code == "429" || e.response_code == "503")
        sleep(BACKOFF_BASE ** retries)
        retry
      end
      raise
    end
  end

  def save_scraping_progress(key, value)
    progress = raw_ingestion.scraping_progress || {}
    progress[key] = value
    raw_ingestion.update_column(:scraping_progress, progress)
  end

  def get_scraping_progress(key)
    raw_ingestion.scraping_progress&.dig(key)
  end
end
