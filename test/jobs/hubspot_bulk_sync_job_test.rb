require "test_helper"

class HubspotBulkSyncJobTest < ActiveJob::TestCase
  test "should enqueue job with recent sync type" do
    assert_enqueued_with(job: HubspotBulkSyncJob, args: [ :recent, { hours: 26 } ]) do
      HubspotBulkSyncJob.perform_later(:recent, hours: 26)
    end
  end

  test "should handle all sync types" do
    fake_service = Object.new
    def fake_service.sync_all_contacts_from_hubspot; end
    def fake_service.sync_stale_contacts_from_hubspot; end
    def fake_service.sync_recently_updated_contacts_from_hubspot(hours:); end

    HubspotSyncService.define_singleton_method(:new) { fake_service }

    job = HubspotBulkSyncJob.new

    assert_nothing_raised do
      job.perform(:all)
      job.perform(:stale)
      job.perform(:recent, hours: 26)
    end
  ensure
    HubspotSyncService.singleton_class.remove_method(:new)
  end

  test "should not raise for unknown sync type" do
    job = HubspotBulkSyncJob.new

    assert_nothing_raised do
      job.perform(:invalid)
    end
  end
end
