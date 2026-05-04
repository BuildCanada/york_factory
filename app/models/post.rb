class Post < ApplicationRecord
  include Feedable, Translatable, Publishable, HasLocalizedMarkdown

  extend Mobility
  translates :title, :summary, backend: :column

  extend FriendlyId
  friendly_id :title_en, use: :history

  has_localized_markdown :body
  has_one_attached :seo_image
  has_one_attached :banner_image

  translatable_fields :title, :summary
  markdown_fields :body

  scope :visible, -> { where(hidden: false) }

  def self.feed_type_label = "blog"
end
