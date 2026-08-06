module Search
  class RunSavedSearchJob < ApplicationJob
    retry_on Turbopuffer::Errors::APIError, wait: :polynomially_longer, attempts: 5
    retry_on Search::Embedding::AzureCohereClient::Error, wait: :polynomially_longer, attempts: 5

    def perform(run_id)
      run = SavedSearchRun.includes(:saved_search).find_by(id: run_id)
      return unless run&.saved_search&.enabled?
      return unless claim(run)

      Search::SavedSearchRunner.new(run).call
    end

    private

    def claim(run)
      claimed = false
      run.with_lock do
        reclaimable = run.status.in?(%w[pending failed]) ||
          (run.status == "running" && run.started_at && run.started_at <= 10.minutes.ago)
        if reclaimable
          run.start!
          claimed = true
        end
      end
      claimed
    end
  end
end
