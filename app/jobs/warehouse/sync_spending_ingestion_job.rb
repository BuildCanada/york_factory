class Warehouse::SyncSpendingIngestionJob < ApplicationJob
  include ActiveJob::Continuable

  retry_on Search::Embedding::AzureCohereClient::Error,
    wait: :polynomially_longer,
    attempts: 6

  def perform(raw_ingestion)
    @raw_ingestion = raw_ingestion

    step :sync_awards do |step|
      awards.find_each(start: step.cursor) do |award|
        sync(award)
        step.advance! from: award.id
      end
    end
  end

  private

  def awards
    @raw_ingestion.spending_awards.where(search_synced_at: nil)
  end

  def sync(award)
    award.sync_to_search!
  end
end
