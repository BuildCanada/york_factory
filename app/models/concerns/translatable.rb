module Translatable
  extend ActiveSupport::Concern

  class_methods do
    def translatable_fields(*fields)
      @translatable_fields = fields if fields.any?
      @translatable_fields || []
    end

    def markdown_fields(*fields)
      @markdown_fields = fields if fields.any?
      @markdown_fields || []
    end

    def hash_fields(*fields)
      @hash_fields = fields if fields.any?
      @hash_fields || []
    end
  end

  included do
    after_commit :enqueue_translation, on: [ :create, :update ], if: :translatable_fields_changed?
  end

  private

  def enqueue_translation
    return if self.class.translatable_fields.empty? && self.class.markdown_fields.empty? && self.class.hash_fields.empty?
    TranslateRecordJob.perform_later(self)
  end

  def translatable_fields_changed?
    return true if previously_new_record?
    changed_attrs = previous_changes.keys.map(&:to_sym)
    en_fields = self.class.translatable_fields.map { |f| :"#{f}_en" }
    (changed_attrs & en_fields).any?
  end
end
