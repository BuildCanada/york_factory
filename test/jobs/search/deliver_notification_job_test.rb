require "test_helper"

class Search::DeliverNotificationJobTest < ActiveJob::TestCase
  setup do
    feed = Warehouse::MediaFeed.create!(
      name: "Email feed #{SecureRandom.hex(4)}",
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
      title: "Email article",
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
      name: "Email alerts #{SecureRandom.hex(4)}",
      realm: "media",
      definition: { version: 1, realm: "media", mode: "filter_only" },
      delivery_mode: "instant",
      delivery_configuration: { channels: [ "email" ] }
    )
    match = @saved_search.matches.create!(searchable: article, state: "buffered")
    @batch = @saved_search.notification_batches.create!(
      mode: "instant",
      scheduled_for: Time.current
    )
    match.update!(notification_batch: @batch)
    @batch.close!
    @delivery = @batch.notification_deliveries.find_by!(channel: "email")
    clear_enqueued_jobs
  end

  test "delivers an email" do
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      Search::DeliverNotificationJob.perform_now(@delivery.id)
    end

    assert_equal "delivered", @delivery.reload.status
    assert_equal({ "provider" => "action_mailer" }, @delivery.provider_response)
    assert_equal "delivered", @batch.reload.state
  end

  test "retries a delivery error" do
    assert_enqueued_jobs 1, only: Search::DeliverNotificationJob do
      failing_job.perform(@delivery.id)
    end

    assert_equal "failed", @delivery.reload.status
    assert_match "SMTP unavailable", @delivery.last_error
    assert @delivery.next_attempt_at.future?
    assert_equal "delivering", @batch.reload.state
  end

  test "marks a delivery dead after the final attempt" do
    @delivery.update!(attempt_count: Search::DeliverNotificationJob::MAX_ATTEMPTS - 1)

    assert_no_enqueued_jobs only: Search::DeliverNotificationJob do
      failing_job.perform(@delivery.id)
    end

    assert_equal "dead", @delivery.reload.status
    assert_equal "dead", @batch.reload.state
  end

  private

  def failing_job
    Search::DeliverNotificationJob.new.tap do |job|
      job.define_singleton_method(:deliver_email) { |_delivery| raise "SMTP unavailable" }
    end
  end
end
