class Post < ApplicationRecord
  include Translatable, Publishable, HasLocalizedRichText

  extend Mobility
  translates :title, :summary, backend: :column

  extend FriendlyId
  friendly_id :title_en, use: :history

  has_localized_rich_text :body
  has_one_attached :seo_image

  translatable_fields :title, :summary
  rich_text_fields :body

  scope :visible, -> { where(hidden: false) }
end
