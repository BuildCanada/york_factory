class Builder < ApplicationRecord
  include Feedable, Translatable, Publishable, HasLocalizedMarkdown

  extend Mobility
  translates :title, :byline, :quote, backend: :column

  extend FriendlyId
  friendly_id :title_en, use: :history
  validates :slug, presence: true, uniqueness: true

  has_localized_markdown :body
  has_localized_markdown :author
  has_one_attached :image

  translatable_fields :title, :byline, :quote
  markdown_fields :body, :author

  def self.feed_type_label = "builder"

  def should_generate_new_friendly_id?
    false
  end
end
