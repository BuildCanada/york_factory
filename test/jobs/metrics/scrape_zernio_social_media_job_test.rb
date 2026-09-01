require "test_helper"

class Metrics::ScrapeZernioSocialMediaJobTest < ActiveJob::TestCase
  class TestJob < Metrics::ScrapeZernioSocialMediaJob
    cattr_accessor :test_scraper

    private

    def scraper = self.class.test_scraper
    def api_key = "test-key"
  end

  test "advances through consecutive analytics pages" do
    pages = []
    daily_accounts = []
    account = Metrics::SocialMediaAccount.create!(
      zernio_account_id: "linkedin-daily", zernio_profile_id: "profile-daily",
      profile_name: "Daily", platform: "linkedin", account_key: "daily",
      username: "daily"
    )
    scraper = Object.new
    scraper.define_singleton_method(:sync_accounts!) { nil }
    scraper.define_singleton_method(:sync_page!) do |page:|
      pages << page
      { processed: 1, next_page: page < 10 ? page + 1 : nil }
    end
    scraper.define_singleton_method(:sync_account_daily_metrics!) do |account_id:|
      daily_accounts << account_id
    end
    scraper.define_singleton_method(:sync_ad_campaigns_page!) do |page:|
      { processed: 0, next_page: nil }
    end
    scraper.define_singleton_method(:sync_ads_page!) do |page:|
      { processed: 0, next_page: nil }
    end

    TestJob.test_scraper = scraper
    TestJob.perform_now

    assert_equal (1..pages.size).to_a, pages
    assert_equal [ account.id ], daily_accounts
  ensure
    TestJob.test_scraper = nil
  end

  test "continues after one account daily metrics request fails" do
    failing_account = Metrics::SocialMediaAccount.create!(
      zernio_account_id: "linkedin-failing", zernio_profile_id: "profile-failing",
      profile_name: "Failing", platform: "linkedin", account_key: "failing",
      username: "failing", ads_status: "connected"
    )
    later_account = Metrics::SocialMediaAccount.create!(
      zernio_account_id: "tiktok-later", zernio_profile_id: "profile-later",
      profile_name: "Later", platform: "tiktok", account_key: "later",
      username: "later"
    )
    daily_accounts = []
    ad_accounts = []
    scraper = Object.new
    scraper.define_singleton_method(:sync_accounts!) { nil }
    scraper.define_singleton_method(:sync_page!) { |page:| { processed: 0, next_page: nil } }
    scraper.define_singleton_method(:sync_account_daily_metrics!) do |account_id:|
      raise Metrics::ZernioClient::Error, "unavailable" if account_id == failing_account.id

      daily_accounts << account_id
    end
    scraper.define_singleton_method(:sync_ad_account!) { |account_id:| ad_accounts << account_id }
    scraper.define_singleton_method(:sync_ad_campaigns_page!) do |page:|
      { processed: 0, next_page: nil }
    end
    scraper.define_singleton_method(:sync_ads_page!) do |page:|
      { processed: 0, next_page: nil }
    end

    TestJob.test_scraper = scraper
    TestJob.perform_now

    assert_equal [ later_account.id ], daily_accounts
    assert_equal [ failing_account.id ], ad_accounts
  ensure
    TestJob.test_scraper = nil
  end
end
