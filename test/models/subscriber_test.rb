require "test_helper"

class SubscriberTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creating a subscriber enqueues a HubSpot form submission" do
    assert_enqueued_with(job: Subscriber::SubmitToHubspotFormJob) do
      Subscriber.create!(email: "new@example.com", first_name: "New", postal_code: "T2P 1J9")
    end
  end

  test "updating a synced field enqueues a HubSpot form submission" do
    assert_enqueued_with(job: Subscriber::SubmitToHubspotFormJob) do
      subscribers(:existing_subscriber).update!(first_name: "Renamed")
    end
  end

  test "touching a subscriber does not enqueue a HubSpot form submission" do
    assert_no_enqueued_jobs(only: Subscriber::SubmitToHubspotFormJob) do
      subscribers(:existing_subscriber).touch
    end
  end

  test "failing to save does not enqueue a HubSpot form submission" do
    assert_no_enqueued_jobs(only: Subscriber::SubmitToHubspotFormJob) do
      Subscriber.create(email: "not-an-email")
    end
  end

  test "submit_to_hubspot_form submits the subscriber through the forms service" do
    received = nil
    HubspotFormsService.define_singleton_method(:submit_subscriber) { |subscriber| received = subscriber }

    subscriber = subscribers(:existing_subscriber)
    subscriber.submit_to_hubspot_form

    assert_equal subscriber, received
  ensure
    HubspotFormsService.singleton_class.remove_method(:submit_subscriber)
  end

  test "stamping pledged_to_vote_at enqueues a direct CRM sync, not a form submission" do
    subscriber = subscribers(:existing_subscriber)

    assert_no_enqueued_jobs(only: Subscriber::SubmitToHubspotFormJob) do
      assert_enqueued_with(job: Subscriber::SyncToHubspotJob) do
        subscriber.update!(pledged_to_vote_at: Time.current)
      end
    end
  end

  test "sync_to_hubspot includes pledged_to_vote_at when the subscriber has pledged" do
    received = nil
    HubspotContact.define_singleton_method(:upsert_hubspot_user) { |**kwargs| received = kwargs }

    subscriber = subscribers(:existing_subscriber)
    subscriber.update!(pledged_to_vote_at: Time.utc(2026, 7, 29, 12, 0))
    subscriber.sync_to_hubspot

    assert_equal Time.utc(2026, 7, 29, 12, 0), received[:properties][:pledged_to_vote_at]
  ensure
    HubspotContact.singleton_class.remove_method(:upsert_hubspot_user)
  end

  test "sync_to_hubspot upserts the HubSpot contact with the subscriber's details" do
    received = nil
    HubspotContact.define_singleton_method(:upsert_hubspot_user) { |**kwargs| received = kwargs }

    subscribers(:existing_subscriber).sync_to_hubspot

    assert_equal "test@example.com", received[:email]
    assert_equal "Test", received[:properties][:firstname]
    assert_equal "User", received[:properties][:lastname]
    assert_equal "K1A 0A6", received[:properties][:postal_code]
    assert received[:properties][:newsletter_subscription]
  ensure
    HubspotContact.singleton_class.remove_method(:upsert_hubspot_user)
  end

  test "sync_to_hubspot omits blank properties so they never overwrite HubSpot data" do
    received = nil
    HubspotContact.define_singleton_method(:upsert_hubspot_user) { |**kwargs| received = kwargs }

    Subscriber.new(email: "blank@example.com").sync_to_hubspot

    assert_equal "blank@example.com", received[:email]
    assert_equal({ newsletter_subscription: true }, received[:properties])
  ensure
    HubspotContact.singleton_class.remove_method(:upsert_hubspot_user)
  end

  test "backfill_hubspot_sync enqueues a staggered CRM sync for every subscriber, not form submissions" do
    Subscriber.create!(email: "another@example.com")

    assert_no_enqueued_jobs(only: Subscriber::SubmitToHubspotFormJob) do
      assert_enqueued_jobs(Subscriber.count, only: Subscriber::SyncToHubspotJob) do
        Subscriber.backfill_hubspot_sync
      end
    end
  end
end
