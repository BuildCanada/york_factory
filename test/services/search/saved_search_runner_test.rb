require "test_helper"

class Search::SavedSearchRunnerTest < ActiveJob::TestCase
  class QueryRunner
    def initialize(rows)
      @rows = rows
    end

    def call(*)
      Search::QueryRunner::Result.new(
        rows: @rows,
        billing: { "billable_logical_bytes_queried" => 100 },
        performance: {},
        query_count: 1
      )
    end
  end

  test "resolves provider IDs directly to searchable source records" do
    article = media_article
    saved_search = SavedSearch.create!(user: users(:member), name: "Direct article matches",
      realm: "media", definition: { version: 1, realm: "media", mode: "filter_only" },
      delivery_mode: "digest", delivery_configuration: { channels: [ "email" ] })
    run = saved_search.runs.create!(scheduled_for: Time.current, from_sequence: 0,
      to_sequence: article.search_index_sequence)

    matches = Search::SavedSearchRunner.new(run,
      query_runner: QueryRunner.new([ { id: article.search_id } ])).call

    assert_equal [ article ], matches.map(&:searchable)
    assert_equal [ "Search::MediaArticle" ], matches.map(&:searchable_type)
    assert_equal article.search_id, matches.sole.match_key
    assert_equal "succeeded", run.reload.status
    assert_equal 1, run.matched_count
    assert_equal article.search_index_sequence, saved_search.reload.cursor_sequence
  end

  private

  def media_article
    source = Search::Source.create!(name: "Runner source #{SecureRandom.hex(4)}", realm: "media",
      strategy: "rss", url: "https://nationalpost.com/feed/", cadence_seconds: 300)
    Search::MediaArticle.new(source: source, external_key: SecureRandom.uuid,
      title: "Matched article", content: "Matched article body", language: "en",
      realm_data: { "content_type" => "article", "publisher_name" => "National Post",
        "publisher_domain" => "nationalpost.com", "authors" => [], "word_count" => 3 }).tap do |article|
      article.publish!
      article.update_columns(search_index_sequence: 12, search_synced_at: Time.current)
    end
  end
end
