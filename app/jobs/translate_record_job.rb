class TranslateRecordJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(record_class, record_id)
    record = record_class.constantize.find_by(id: record_id)
    return unless record

    TranslationService.new.translate_record(record)
  end
end
