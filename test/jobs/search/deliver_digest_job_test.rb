require "test_helper"

class Search::DeliverDigestJobTest < ActiveJob::TestCase
  setup do
    feed = Warehouse::MediaFeed.create!(
      name: "Digest feed #{SecureRandom.hex(4)}",
      strategy: "rss",
      url: "https://nationalpost.com/feed/",
      cadence_seconds: 300,
      publisher_name: "National Post",
      publisher_domain: "nationalpost.com",
      language: "en"
    )
    article = Warehouse::MediaArticle.new(
      feed:,
      external_key: SecureRandom.uuid,
      title: "Digest article",
      content: "Body",
      language: "en",
      realm_data: {
        "content_type" => "article",
        "publisher_name" => "National Post",
        "publisher_domain" => "nationalpost.com",
        "authors" => [],
        "word_count" => 1
      }
    )
    article.publish!
    @saved_search = SavedSearch.create!(
      user: users(:member),
      name: "Digest alerts #{SecureRandom.hex(4)}",
      realm: "media",
      definition: { version: 1, realm: "media", mode: "filter_only" },
      delivery_mode: "digest",
      delivery_configuration: { channels: [ "email", "webhook" ], webhook_url: "https://example.com/hook" }
    )
    match = @saved_search.matches.create!(searchable: article, state: "buffered")
    @batch = @saved_search.notification_batches.create!(
      mode: "digest",
      scheduled_for: 1.minute.ago
    )
    match.update!(notification_batch: @batch)
    clear_enqueued_jobs
  end

  test "closes a due digest and directly enqueues its channel deliveries" do
    assert_enqueued_jobs 2, only: Search::DeliverNotificationJob do
      Search::DeliverDigestJob.perform_now(@batch.id)
    end

    assert_equal "closed", @batch.reload.state
    assert @batch.payload.present?
    assert_equal %w[email webhook], @batch.notification_deliveries.order(:channel).pluck(:channel)
    assert_equal [ "dispatching" ], @batch.saved_search_matches.distinct.pluck(:state)
  end

  test "a duplicate digest job does not create duplicate deliveries" do
    Search::DeliverDigestJob.perform_now(@batch.id)
    delivery_ids = @batch.notification_deliveries.order(:id).ids
    clear_enqueued_jobs

    assert_enqueued_jobs 2, only: Search::DeliverNotificationJob do
      Search::DeliverDigestJob.perform_now(@batch.id)
    end

    assert_equal delivery_ids, @batch.notification_deliveries.order(:id).ids
  end

  test "an early job reschedules itself at the persisted due time" do
    @batch.update!(scheduled_for: 1.hour.from_now)

    assert_enqueued_with(job: Search::DeliverDigestJob, args: [ @batch.id ], at: @batch.scheduled_for) do
      Search::DeliverDigestJob.perform_now(@batch.id)
    end

    assert_equal "open", @batch.reload.state
    assert_empty @batch.notification_deliveries
  end
end
