module Translatable
  extend ActiveSupport::Concern

  class_methods do
    def translatable_fields(*fields)
      @translatable_fields = fields if fields.any?
      @translatable_fields || []
    end

    def rich_text_fields(*fields)
      @rich_text_fields = fields if fields.any?
      @rich_text_fields || []
    end
  end

  included do
    after_commit :enqueue_translation, on: [:create, :update], if: :translatable_fields_changed?
  end

  private

  def enqueue_translation
    return if self.class.translatable_fields.empty? && self.class.rich_text_fields.empty?
    TranslateRecordJob.perform_later(self.class.name, id)
  end

  def translatable_fields_changed?
    return true if previously_new_record?
    changed_attrs = previous_changes.keys.map(&:to_sym)
    en_fields = self.class.translatable_fields.map { |f| :"#{f}_en" }
    (changed_attrs & en_fields).any?
  end
end
