require "test_helper"

class WebflowSyncJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "retries when sync has errors" do
    success_result = WebflowSyncService::Result.new(
      team_members: 0, memos: 0, posts: 0, tools: 0, builders: 0,
      errors: [ "Memo 'Test': slug can't be blank" ]
    )

    ENV["WEBFLOW_API_KEY"] = "test-key"
    original_sync = WebflowSyncService.instance_method(:sync!)
    WebflowSyncService.define_method(:sync!) { success_result }

    assert_enqueued_with(job: WebflowSyncJob) do
      WebflowSyncJob.perform_now
    end
  ensure
    WebflowSyncService.define_method(:sync!, original_sync) if original_sync
    ENV.delete("WEBFLOW_API_KEY")
  end

  test "completes without retry when sync succeeds" do
    success_result = WebflowSyncService::Result.new(
      team_members: 5, memos: 3, posts: 2, tools: 1, builders: 1,
      errors: []
    )

    ENV["WEBFLOW_API_KEY"] = "test-key"
    original_sync = WebflowSyncService.instance_method(:sync!)
    WebflowSyncService.define_method(:sync!) { success_result }

    assert_no_enqueued_jobs(only: WebflowSyncJob) do
      WebflowSyncJob.perform_now
    end
  ensure
    WebflowSyncService.define_method(:sync!, original_sync) if original_sync
    ENV.delete("WEBFLOW_API_KEY")
  end
end
