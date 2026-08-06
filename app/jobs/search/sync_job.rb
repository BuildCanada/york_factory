module Search
  class SyncJob < ApplicationJob
    retry_on Search::Embedding::AzureCohereClient::Error,
      wait: :polynomially_longer,
      attempts: 6

    def perform(record)
      raise ArgumentError, "record is not searchable" unless record.respond_to?(:sync_to_search!)

      record.sync_to_search!
    end
  end
end
