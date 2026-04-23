require "test_helper"

class BuildTorontoSyncServiceTest < ActiveSupport::TestCase
  SITES_RESPONSE = {
    "sites" => [
      { "id" => "site-other", "displayName" => "Other Site",    "shortName" => "other" },
      { "id" => "site-bt",    "displayName" => "Build Toronto", "shortName" => "buildtoronto" }
    ]
  }.freeze

  COLLECTIONS_RESPONSE = {
    "collections" => [
      { "id" => "col-builders", "displayName" => "Builders", "slug" => "builders" },
      { "id" => "col-memos",    "displayName" => "Memos",    "slug" => "memos" }
    ]
  }.freeze

  BUILDER_ITEMS = [
    {
      "id" => "builder-1",
      "fieldData" => {
        "name" => "Jane Toronto",
        "title" => "Policy Advisor",
        "linkedin" => "https://linkedin.com/in/jane",
        "twitter" => "",
        "slug" => "jane-toronto"
      }
    }
  ].freeze

  MEMO_ITEMS = [
    {
      "id" => "item-1",
      "createdOn" => "2026-04-01T12:00:00Z",
      "fieldData" => {
        "slug" => "toronto-housing",
        "name" => "Toronto Housing Plan",
        "body" => "<p>Hello Toronto.</p>",
        "builder" => "builder-1",
        "twitter-embed" => nil
      }
    }
  ].freeze

  class FakeClient
    attr_reader :get_calls, :fetch_calls

    def initialize(sites:, collections:, items_by_collection:)
      @sites = sites
      @collections = collections
      @items_by_collection = items_by_collection
      @get_calls = []
      @fetch_calls = []
    end

    def get(path)
      @get_calls << path
      case path
      when "/sites" then @sites
      when %r{\A/sites/.+/collections\z} then @collections
      else raise "unexpected path: #{path}"
      end
    end

    def fetch_all_items(collection_id)
      @fetch_calls << collection_id
      @items_by_collection.fetch(collection_id, [])
    end
  end

  def fake_client(items_by_collection: default_items)
    FakeClient.new(
      sites: SITES_RESPONSE,
      collections: COLLECTIONS_RESPONSE,
      items_by_collection: items_by_collection
    )
  end

  def default_items
    { "col-builders" => BUILDER_ITEMS, "col-memos" => MEMO_ITEMS }
  end

  test "raises if no token provided and no client injected" do
    error = assert_raises(BuildTorontoSyncService::SyncError) do
      BuildTorontoSyncService.new(api_token: "")
    end
    assert_match(/Missing build_toronto Webflow token/, error.message)
  end

  test "discovers toronto site, finds memo + builder collections, syncs both, and links author" do
    client = fake_client
    result = BuildTorontoSyncService.new(client: client).sync!

    assert_equal 1, result.memos
    assert_empty result.errors
    assert_includes client.get_calls, "/sites"
    assert_includes client.get_calls, "/sites/site-bt/collections"
    assert_includes client.fetch_calls, "col-memos"
    assert_includes client.fetch_calls, "col-builders"

    author = TeamMember.find_by(name: "Jane Toronto", role: "memo_author")
    assert_not_nil author, "expected memo_author TeamMember to be created"
    assert_equal "Policy Advisor", author.title_en
    assert_equal "https://linkedin.com/in/jane", author.linkedin_url

    memo = Memo.find_by(slug: "toronto-housing", publication: "build_toronto")
    assert_not_nil memo
    assert_equal author, memo.author
  end

  test "is idempotent — re-running does not duplicate memos or authors" do
    BuildTorontoSyncService.new(client: fake_client).sync!
    assert_difference -> { Memo.where(publication: "build_toronto").count }, 0 do
      assert_difference -> { TeamMember.where(role: "memo_author", name: "Jane Toronto").count }, 0 do
        BuildTorontoSyncService.new(client: fake_client).sync!
      end
    end
  end

  test "synced memo does not appear via without_publication scope" do
    BuildTorontoSyncService.new(client: fake_client).sync!
    memo = Memo.find_by(slug: "toronto-housing", publication: "build_toronto")
    assert_not_nil memo
    refute Memo.without_publication.exists?(id: memo.id)
  end

  test "raises when no memo-like collection exists" do
    bare = { "collections" => [ { "id" => "x", "displayName" => "Other", "slug" => "other" } ] }
    client = FakeClient.new(sites: SITES_RESPONSE, collections: bare, items_by_collection: {})
    assert_raises(BuildTorontoSyncService::SyncError) do
      BuildTorontoSyncService.new(client: client).sync!
    end
  end

  test "memo without a builder reference still syncs, with nil author" do
    memos = [ MEMO_ITEMS.first.deep_dup.tap { |h| h["fieldData"].delete("builder") } ]
    client = fake_client(items_by_collection: { "col-builders" => [], "col-memos" => memos })
    BuildTorontoSyncService.new(client: client).sync!

    memo = Memo.find_by(slug: "toronto-housing", publication: "build_toronto")
    assert_not_nil memo
    assert_nil memo.author
  end
end
