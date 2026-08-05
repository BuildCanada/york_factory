require "test_helper"

class Admin::SearchControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  class FakeQueryRunner
    class << self
      attr_accessor :calls, :result
    end

    def call(definition, **options)
      self.class.calls ||= []
      self.class.calls << { definition:, options: }
      self.class.result
    end
  end

  setup do
    @original_factory = Admin::SearchController.query_runner_factory
    Admin::SearchController.query_runner_factory = -> { FakeQueryRunner.new }
    FakeQueryRunner.calls = []
    FakeQueryRunner.result = Search::QueryRunner::Result.new(
      rows: [
        {
          "id" => "media-1",
          "realm" => "media",
          "record_type" => "article",
          "title" => "Canada announces a housing policy",
          "summary" => "A result returned by the provider.",
          "canonical_url" => "https://nationalpost.com/news/housing",
          "publisher_name" => "National Post",
          "published_at" => "2026-08-05T12:00:00Z",
          "$dist" => 0.21
        }
      ],
      billing: { "billable_logical_bytes_queried" => 1_280_000_000 },
      performance: { "server_total_ms" => 14 },
      query_count: 2
    )
  end

  teardown do
    Admin::SearchController.query_runner_factory = @original_factory
  end

  test "redirects unauthenticated users" do
    get admin_search_path

    assert_redirected_to new_user_session_path
  end

  test "renders the search workbench and schema vocabulary" do
    sign_in_admin

    get admin_search_path

    assert_response :success
    assert_select "#search-workbench"
    assert_select "form#search-workbench[data-turbo='false']"
    assert_select "#search-filters"
    assert_select "input[type='search'][enterkeyhint='search']"
    assert_select "#saved-searches"
    assert_select "option[value='media']"
    assert_match "publisher_domain", response.body
    assert_select "[aria-label='Search index status']", text: /Pending/
    assert_select ".search-index-status-item span", text: "Records"
  end

  test "runs a hybrid media query and renders provider telemetry" do
    sign_in_admin

    post admin_search_path, params: {
      operation: "query",
      search: {
        realm: "media",
        mode: "hybrid",
        text: "housing policy",
        language: "en",
        lexical_match: "all_tokens",
        semantic_max_distance: "0.5",
        limit: "12",
        publisher_domain: "nationalpost.com"
      }
    }

    assert_response :success
    assert_select "#search-results"
    assert_select "#search-results h1", text: /1 result/
    assert_select "a[href='#search-results']", count: 0
    assert_match "Canada announces a housing policy", response.body
    assert_match "billable_logical_bytes_queried", response.body
    assert_equal 1, FakeQueryRunner.calls.length
    call = FakeQueryRunner.calls.first
    assert_equal "media", call[:definition]["realm"]
    assert_equal 0.5, call[:definition]["semantic_max_distance"]
    assert_equal({ "field" => "publisher_domain", "op" => "eq", "value" => "nationalpost.com" }, call[:definition]["filters"])
    assert_equal 12, call[:options][:limit]
  end

  test "creates a media saved search with delivery configuration" do
    sign_in_admin

    assert_difference("SavedSearch.count", 1) do
      post admin_search_path, params: {
        operation: "save",
        search: {
          name: "National Post housing",
          realm: "media",
          mode: "hybrid",
          text: "housing policy",
          language: "en",
          lexical_match: "phrase",
          semantic_max_distance: "0.45",
          publisher_domain: "nationalpost.com",
          content_type: "article",
          start_policy: "future_only",
          poll_interval_seconds: "300",
          delivery_mode: "instant",
          email: "1",
          notify_on_update: "1"
        }
      }
    end

    saved_search = users(:admin).saved_searches.order(:created_at).last
    assert_redirected_to admin_search_path
    assert_equal "National Post housing", saved_search.name
    assert_equal "media", saved_search.realm
    assert_equal "hybrid", saved_search.definition["mode"]
    assert_equal 2, saved_search.definition.dig("filters", "all").length
    assert_equal %w[email], saved_search.delivery_configuration["channels"]
    assert_equal 300, saved_search.poll_interval_seconds
    assert saved_search.notify_on_update?
  end

  test "rejects malformed advanced filters" do
    sign_in_admin

    assert_no_difference("SavedSearch.count") do
      post admin_search_path, params: {
        operation: "save",
        search: {
          realm: "media",
          mode: "filter_only",
          filters_json: "not-json",
          email: "1"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#search-errors"
  end

  test "tests and deletes an owned saved search" do
    sign_in_admin
    saved_search = create_saved_search(users(:admin))

    post admin_test_saved_search_path(saved_search)

    assert_response :success
    assert_match saved_search.name, response.body
    assert_equal 1, FakeQueryRunner.calls.length
    assert_equal saved_search.definition, FakeQueryRunner.calls.first[:definition]

    assert_difference("SavedSearch.count", -1) do
      delete admin_search_saved_search_path(saved_search)
    end
    assert_redirected_to admin_search_path
  end

  test "does not expose another user's saved search" do
    sign_in_admin
    saved_search = create_saved_search(users(:member))

    post admin_test_saved_search_path(saved_search)

    assert_response :not_found
  end

  private

  def create_saved_search(user)
    user.saved_searches.create!(
      name: "Media test #{SecureRandom.hex(3)}",
      realm: "media",
      definition: {
        "version" => 1,
        "realm" => "media",
        "mode" => "lexical",
        "language" => "en",
        "lexical_match" => "all_tokens",
        "text" => "housing"
      },
      poll_interval_seconds: 60,
      cursor_sequence: 0,
      start_policy: "future_only",
      delivery_mode: "instant",
      delivery_configuration: { "channels" => [ "email" ] },
      timezone: "UTC",
      next_run_at: Time.current
    )
  end
end
