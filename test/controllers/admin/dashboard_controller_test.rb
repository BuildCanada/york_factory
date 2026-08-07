require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    @original_scrape_status = Admin::DashboardController.scrape_status
    Admin::DashboardController.scrape_status = scrape_status_with({})
    sign_in_admin
  end

  teardown do
    Admin::DashboardController.scrape_status = @original_scrape_status
  end

  test "redirects the old admin dashboard URL to scraping" do
    get "/admin"

    assert_redirected_to admin_root_path
    assert_equal "/admin/scraping", admin_root_path
  end

  test "renders source run times and run controls on scraping dashboard" do
    source = create_source(name: "econ_admin_source", fetch_frequency: "weekly", last_fetched_at: 2.days.ago)

    travel_to Time.zone.parse("2026-08-06 08:00") do
      get admin_root_path
    end

    assert_response :success
    assert_select "h1", "Scraping"
    assert_select "td", text: /#{Regexp.escape(source.name)}/
    assert_select "td", text: /Weekly/
    assert_select "time[datetime='#{source.last_fetched_at.iso8601}']"
    assert_select "time[datetime='2026-08-07T07:00:00Z']"
    assert_select "td", text: /every day at 7am/
    assert_select "form[action='#{admin_run_scraping_source_path(source)}'] button", text: "Run now"
  end

  test "shows a running scrape batch and disables duplicate runs" do
    source = create_source(fetch_frequency: "daily")

    Admin::DashboardController.scrape_status = scrape_status_with(source.id => "running")
    get admin_root_path

    assert_response :success
    assert_select "[aria-label='Scrape batch status']", text: /Running/
    assert_select "td", text: "Running"
    assert_select "button[disabled]", text: "Run now"
  end

  test "queues a source scrape" do
    source = create_source(fetch_frequency: "manual")

    assert_enqueued_with(job: Warehouse::Source::Fetcher::FetchJob, queue: "scraping") do
      post admin_run_scraping_source_path(source)
    end

    assert_redirected_to admin_root_path
    assert_equal "#{source.name} scrape queued.", flash[:notice]
  end

  test "renders ingestions with existing records" do
    source = create_source
    source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test.csv",
      checksum: SecureRandom.hex(32),
      status: "complete"
    )

    get admin_ingestions_path

    assert_response :success
    assert_select "h1", "Ingestions"
    assert_select "td", text: source.name
    assert_select "th", text: "Rows", count: 0
  end

  private

  def scrape_status_with(states)
    Object.new.tap do |status|
      status.define_singleton_method(:active) { states }
    end
  end

  def create_source(name: nil, fetch_frequency: nil, last_fetched_at: nil)
    Warehouse::Source.create!(
      name: name || "admin_source_#{SecureRandom.hex(4)}",
      url: "https://example.com/data.csv",
      format: "csv",
      fetch_frequency:,
      last_fetched_at:
    )
  end
end
