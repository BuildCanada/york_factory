require "test_helper"

class Search::SavedSearchFanoutJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    article = Warehouse::MediaArticle.new(
      external_key: SecureRandom.uuid,
      title: "Fanout article",
      content: "Fanout body",
      language: "en",
      realm_data: {
        "content_type" => "article",
        "publisher_name" => "National Post",
        "publisher_domain" => "nationalpost.com",
        "authors" => [],
        "word_count" => 2
      }
    )
    article.publish!
    article.update_columns(search_index_sequence: 10, search_synced_at: Time.current)

    @saved_search = SavedSearch.create!(
      user: users(:member),
      name: "Due media search",
      realm: "media",
      definition: { version: 1, realm: "media", mode: "filter_only" },
      poll_interval_seconds: 300,
      next_run_at: 1.minute.ago,
      delivery_configuration: { channels: [ "email" ] }
    )
    clear_enqueued_jobs
  end

  test "creates one run for each due search and fans it out" do
    at = Time.current

    assert_difference -> { @saved_search.runs.count }, 1 do
      assert_enqueued_jobs 1, only: Search::RunSavedSearchJob do
        Search::SavedSearchFanoutJob.perform_now(at:)
      end
    end

    run = @saved_search.runs.sole
    assert_equal 10, run.to_sequence
    assert_enqueued_with(job: Search::RunSavedSearchJob, args: [ run.id ])
    assert_operator @saved_search.reload.next_run_at, :>, at
  end

  test "a later fanout does not create a duplicate cadence run" do
    at = Time.current

    Search::SavedSearchFanoutJob.perform_now(at:)
    assert_no_difference -> { @saved_search.runs.count } do
      Search::SavedSearchFanoutJob.perform_now(at:)
    end
  end

  test "re-enqueues a stranded pending run" do
    @saved_search.update_columns(next_run_at: 1.hour.from_now)
    run = @saved_search.runs.create!(
      scheduled_for: 1.minute.ago,
      from_sequence: 0,
      to_sequence: 10
    )

    assert_enqueued_with(job: Search::RunSavedSearchJob, args: [ run.id ]) do
      Search::SavedSearchFanoutJob.perform_now
    end
  end
end
