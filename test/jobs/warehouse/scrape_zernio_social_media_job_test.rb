require "test_helper"

class Warehouse::ScrapeZernioSocialMediaJobTest < ActiveJob::TestCase
  class TestJob < Warehouse::ScrapeZernioSocialMediaJob
    cattr_accessor :test_scraper

    private

    def scraper = self.class.test_scraper
    def api_key = "test-key"
  end

  test "advances through consecutive analytics pages" do
    pages = []
    scraper = Object.new
    scraper.define_singleton_method(:sync_accounts!) { nil }
    scraper.define_singleton_method(:sync_page!) do |page:|
      pages << page
      { processed: 1, next_page: page < 10 ? page + 1 : nil }
    end

    TestJob.test_scraper = scraper
    TestJob.perform_now

    assert_equal (1..pages.size).to_a, pages
  ensure
    TestJob.test_scraper = nil
  end
end
