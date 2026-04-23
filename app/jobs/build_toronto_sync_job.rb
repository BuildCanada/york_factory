class BuildTorontoSyncJob < ApplicationJob
  queue_as :default
  retry_on BuildTorontoSyncService::SyncError, wait: :polynomially_longer, attempts: 3

  def perform
    result = BuildTorontoSyncService.new.sync!

    if result.errors.any?
      raise BuildTorontoSyncService::SyncError,
            "Sync completed with #{result.errors.size} errors: #{result.errors.first(5).join("; ")}"
    end
  end
end
