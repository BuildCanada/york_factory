class Faq < ApplicationRecord
  include Translatable, Publishable, HasLocalizedRichText

  extend Mobility
  translates :question, :answer_text, backend: :column

  has_localized_rich_text :answer

  scope :ordered, -> { order(:position) }

  translatable_fields :question, :answer_text
  rich_text_fields :answer
end
