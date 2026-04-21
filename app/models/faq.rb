class Faq < ApplicationRecord
  include Translatable, Publishable, HasLocalizedMarkdown

  extend Mobility
  translates :question, :answer_text, backend: :column

  has_localized_markdown :answer

  scope :ordered, -> { order(:position) }

  translatable_fields :question, :answer_text
  markdown_fields :answer
end
