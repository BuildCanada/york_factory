class Post < ApplicationRecord
  include Feedable, Translatable, Publishable, HasLocalizedMarkdown, ValidatesSlugAvailability

  extend Mobility
  translates :title, :summary, backend: :column

  extend FriendlyId
  friendly_id :title_en, use: :history
  validates :slug, presence: true, uniqueness: true

  has_localized_markdown :body
  has_one_attached :seo_image
  has_one_attached :banner_image

  translatable_fields :title, :summary
  markdown_fields :body

  scope :visible, -> { where(hidden: false) }

  def self.feed_type_label = "blog"

  def should_generate_new_friendly_id?
    false
  end
end
