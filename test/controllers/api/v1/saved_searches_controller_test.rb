require "test_helper"

class Api::V1::SavedSearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @oauth_app = Doorkeeper::Application.create!(name: "Saved search tests",
      redirect_uri: "https://example.com/callback", scopes: "", confidential: true, trusted: true)
    feed = Warehouse::MediaFeed.create!(name: "API checkpoint #{SecureRandom.hex(4)}",
      strategy: "rss", url: "https://nationalpost.com/feed/", cadence_seconds: 300,
      publisher_name: "National Post", publisher_domain: "nationalpost.com", language: "en")
    @article = Warehouse::MediaArticle.new(feed:,
      external_key: SecureRandom.uuid, title: "Checkpoint", content: "Body", language: "en",
      realm_data: { "content_type" => "article", "publisher_name" => "National Post",
        "publisher_domain" => "nationalpost.com", "authors" => [], "word_count" => 1 })
    @article.publish!
    @article.update_columns(search_index_sequence: 42, search_synced_at: Time.current)
  end

  test "create starts future-only searches at the active checkpoint and reveals a new webhook secret once" do
    post api_v1_saved_searches_url, params: {
      saved_search: {
        name: "News hook",
        realm: "media",
        definition: { version: 1, realm: "media", mode: "filter_only" },
        delivery_configuration: {
          channels: [ "webhook" ], webhook_url: "https://example.com/search-hook"
        }
      }
    }, headers: auth(users(:member)), as: :json

    assert_response :created
    body = response.parsed_body
    saved_search = SavedSearch.find(body.fetch("id"))
    assert_equal 42, saved_search.cursor_sequence
    assert body.fetch("webhook_secret").present?

    get api_v1_saved_search_url(saved_search), headers: auth(users(:member))
    assert_response :success
    refute response.parsed_body.key?("webhook_secret")
  end

  test "a backfill definition edit resets the cursor and advances its version" do
    saved_search = create_saved_search(user: users(:member), cursor_sequence: 40)

    patch api_v1_saved_search_url(saved_search), params: {
      saved_search: {
        start_policy: "backfill",
        definition: { version: 1, realm: "media", mode: "filter_only",
          filters: { all: [ { field: "publisher_domain", op: "eq", value: "nationalpost.com" } ] } }
      }
    }, headers: auth(users(:member)), as: :json

    assert_response :success
    saved_search.reload
    assert_equal 0, saved_search.cursor_sequence
    assert_equal 2, saved_search.definition_version
    assert saved_search.next_run_at <= Time.current
  end

  test "a user cannot read another user's saved search" do
    saved_search = create_saved_search(user: users(:admin))

    get api_v1_saved_search_url(saved_search), headers: auth(users(:member))

    assert_response :not_found
  end

  test "saved search endpoints require OAuth" do
    get api_v1_saved_searches_url

    assert_response :unauthorized
  end

  test "matches expose their searchable source record" do
    saved_search = create_saved_search(user: users(:member))
    saved_search.matches.create!(searchable: @article)

    get api_v1_saved_search_matches_url(saved_search), headers: auth(users(:member))

    assert_response :success
    match = response.parsed_body.fetch("data").sole
    assert_equal "Warehouse::MediaArticle", match.fetch("searchable_type")
    assert_equal @article.id, match.fetch("searchable_id")
    assert_equal @article.title, match.fetch("title")
    assert_nil match["url"]
  end

  private

  def create_saved_search(user:, cursor_sequence: 0)
    SavedSearch.create!(user:, name: "News", realm: "media", cursor_sequence:,
      definition: { version: 1, realm: "media", mode: "filter_only" },
      delivery_configuration: { channels: [ "email" ] })
  end

  def auth(user)
    token = Doorkeeper::AccessToken.create!(application: @oauth_app, scopes: "public",
      resource_owner_id: user.id, expires_in: 7_200)
    { "Authorization" => "Bearer #{token.token}" }
  end
end
