class WebflowSyncJob < ApplicationJob
  queue_as :default
  retry_on WebflowSyncService::SyncError, wait: :polynomially_longer, attempts: 3

  def perform
    result = WebflowSyncService.new.sync!

    if result.errors.any?
      raise WebflowSyncService::SyncError, "Sync completed with #{result.errors.size} errors: #{result.errors.first(5).join("; ")}"
    end
  end
end
