require "test_helper"

class HubspotContactSyncJobTest < ActiveJob::TestCase
  test "retries at the delay requested by HubSpot" do
    contact = hubspot_contacts(:one)
    error = TransientError.new("rate limited", retry_after: 120)
    stub_sync(error)
    job = HubspotContact::SyncToHubspotJob.new(contact)
    job.executions = 1

    assert_enqueued_with(job: HubspotContact::SyncToHubspotJob, args: [ contact ], at: 120.seconds.from_now) do
      job.perform_now
    end
  ensure
    HubspotSyncService.singleton_class.remove_method(:sync_contact_to_hubspot)
  end

  test "raises after the final retry attempt" do
    contact = hubspot_contacts(:one)
    error = TransientError.new("rate limited", retry_after: 120)
    stub_sync(error)
    job = HubspotContact::SyncToHubspotJob.new(contact)
    job.executions = HubspotSyncService::MAX_ATTEMPTS - 1

    assert_raises(TransientError) { job.perform_now }
    assert_no_enqueued_jobs only: HubspotContact::SyncToHubspotJob
  ensure
    HubspotSyncService.singleton_class.remove_method(:sync_contact_to_hubspot)
  end

  private

  def stub_sync(error)
    HubspotSyncService.define_singleton_method(:sync_contact_to_hubspot) { |_contact| raise error }
  end
end
