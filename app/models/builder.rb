class Builder < ApplicationRecord
  include Feedable, Translatable, Publishable, HasLocalizedRichText

  extend Mobility
  translates :title, :byline, :quote, backend: :column

  extend FriendlyId
  friendly_id :title_en, use: :history

  has_localized_rich_text :body
  has_localized_rich_text :author
  has_one_attached :image

  translatable_fields :title, :byline, :quote
  rich_text_fields :body, :author

  def self.feed_type_label = "builder"
end
