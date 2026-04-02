class TranslateRecordJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(record)
    TranslationService.new.translate_record(record)
  end
end
