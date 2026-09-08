require "test_helper"

class SubscriberTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creating a subscriber enqueues a HubSpot form submission" do
    assert_enqueued_with(job: Subscriber::SubmitToHubspotFormJob) do
      Subscriber.create!(email: "new@example.com", first_name: "New",
        postal_code: "T2P 1J9", newsletter_opt_in: true)
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
    received = received_form = nil
    original = HubspotFormsService.method(:submit_subscriber)
    HubspotFormsService.define_singleton_method(:submit_subscriber) do |subscriber, form:|
      received = subscriber
      received_form = form
    end

    subscriber = subscribers(:existing_subscriber)
    subscriber.submit_to_hubspot_form

    assert_equal subscriber, received
    assert_equal :subscriber, received_form
  ensure
    HubspotFormsService.define_singleton_method(:submit_subscriber, original) if original
  end

  test "submit_to_hubspot_form passes the requested form to the service" do
    received_form = nil
    original = HubspotFormsService.method(:submit_subscriber)
    HubspotFormsService.define_singleton_method(:submit_subscriber) { |_subscriber, form:| received_form = form }

    subscribers(:existing_subscriber).submit_to_hubspot_form(:pledge)

    assert_equal :pledge, received_form
  ensure
    HubspotFormsService.define_singleton_method(:submit_subscriber, original) if original
  end

  test "creating a subscriber flagged as pledging does not enqueue a subscriber form submission" do
    assert_no_enqueued_jobs(only: Subscriber::SubmitToHubspotFormJob) do
      Subscriber.create!(email: "pledger@example.com", first_name: "New", postal_code: "M5V 1A1", pledging: true)
    end
  end

  test "stamping pledged_to_vote_at enqueues a pledge form submission and a direct CRM sync" do
    subscriber = subscribers(:existing_subscriber)

    assert_enqueued_with(job: Subscriber::SubmitToHubspotFormJob, args: [ subscriber, :pledge ]) do
      assert_enqueued_with(job: Subscriber::SyncToHubspotJob) do
        subscriber.update!(pledged_to_vote_at: Time.current)
      end
    end
  end

  test "sync_to_hubspot includes pledged_to_vote_at when the subscriber has pledged" do
    received = capturing_hubspot_upsert do
      subscriber = subscribers(:existing_subscriber)
      subscriber.update!(pledged_to_vote_at: Time.utc(2026, 7, 29, 12, 0))
      subscriber.sync_to_hubspot
    end

    assert_equal Time.utc(2026, 7, 29, 12, 0), received[:properties][:pledged_to_vote_at]
  end

  test "sync_to_hubspot upserts the HubSpot contact with the subscriber's details" do
    received = capturing_hubspot_upsert do
      subscribers(:existing_subscriber).sync_to_hubspot
    end

    assert_equal "test@example.com", received[:email]
    assert_equal "Test", received[:properties][:firstname]
    assert_equal "User", received[:properties][:lastname]
    assert_equal "K1A 0A6", received[:properties][:postal_code]
    assert received[:properties][:newsletter_subscription]
  end

  test "sync_to_hubspot omits blank properties so they never overwrite HubSpot data" do
    received = capturing_hubspot_upsert do
      Subscriber.new(email: "blank@example.com").sync_to_hubspot
    end

    assert_equal "blank@example.com", received[:email]
    # Only the opt-in survives compaction, and it is false because nobody asked.
    assert_equal({ newsletter_subscription: false }, received[:properties])
  end

  test "backfill_hubspot_sync enqueues a staggered CRM sync for every subscriber, not form submissions" do
    Subscriber.create!(email: "another@example.com")

    assert_no_enqueued_jobs(only: Subscriber::SubmitToHubspotFormJob) do
      assert_enqueued_jobs(Subscriber.count, only: Subscriber::SyncToHubspotJob) do
        Subscriber.backfill_hubspot_sync
      end
    end
  end

  # Submitting the HubSpot subscriber form is what subscribes someone — it
  # exists to fire the signup workflows — so a row that never asked for mail
  # must not submit it. A survey response requires a subscriber, so those rows
  # are common.
  test "a subscriber who did not opt in enqueues no HubSpot form submission" do
    assert_no_enqueued_jobs(only: Subscriber::SubmitToHubspotFormJob) do
      Subscriber.create!(email: "declined@example.com", first_name: "De",
        postal_code: "T2P 1J9", newsletter_opt_in: false)
    end
  end

  test "opting in later enqueues the form even when nothing else changed" do
    subscriber = Subscriber.create!(email: "later@example.com", newsletter_opt_in: false)

    assert_enqueued_with(job: Subscriber::SubmitToHubspotFormJob) do
      subscriber.update!(newsletter_opt_in: true)
    end
  end

  # An opt-out cannot travel through the form — submitting it is what
  # subscribes you — so it has to reach HubSpot as a direct CRM sync or the
  # contact stays subscribed there.
  test "opting out enqueues a direct CRM sync" do
    subscriber = Subscriber.create!(email: "leaving@example.com", newsletter_opt_in: true)

    assert_enqueued_with(job: Subscriber::SyncToHubspotJob) do
      subscriber.update!(newsletter_opt_in: false)
    end
  end

  test "a name change on an opted-out subscriber still enqueues no form" do
    subscriber = Subscriber.create!(email: "quiet@example.com", newsletter_opt_in: false)

    assert_no_enqueued_jobs(only: Subscriber::SubmitToHubspotFormJob) do
      subscriber.update!(first_name: "Renamed")
    end
  end

  # false is blank, so a properties hash run through compact_blank drops the
  # opt-out entirely and leaves the CRM subscribed. This is the regression.
  test "sync_to_hubspot sends the opt-out rather than dropping it" do
    received = capturing_hubspot_upsert do
      Subscriber.create!(email: "optout@example.com", first_name: "Op",
        newsletter_opt_in: false).sync_to_hubspot
    end

    assert_equal false, received[:properties][:newsletter_subscription]
  end

  test "sync_to_hubspot sends the opt-in for a subscriber who asked for mail" do
    received = capturing_hubspot_upsert do
      Subscriber.create!(email: "optin@example.com", first_name: "In",
        newsletter_opt_in: true).sync_to_hubspot
    end

    assert_equal true, received[:properties][:newsletter_subscription]
  end

  private

  # upsert_hubspot_user is a `def self.` method, so a stub defined with
  # define_singleton_method replaces it in place and remove_method deletes the
  # real one along with the stub — after which every later test in this process
  # sees NoMethodError. Put the original back instead.
  def capturing_hubspot_upsert
    original = HubspotContact.method(:upsert_hubspot_user)
    received = nil
    HubspotContact.define_singleton_method(:upsert_hubspot_user) { |**kwargs| received = kwargs }
    yield
    received
  ensure
    HubspotContact.singleton_class.send(:remove_method, :upsert_hubspot_user)
    HubspotContact.define_singleton_method(:upsert_hubspot_user, original)
  end
end
