class FeedItem < ApplicationRecord
  include Translatable, Publishable, HasLocalizedRichText

  extend Mobility
  translates :title, :subtitle, backend: :column

  ITEM_TYPES = %w[blog substack x tiktok ig youtube].freeze

  has_localized_rich_text :body
  has_one_attached :image
  has_one_attached :author_photo

  validates :item_type, presence: true, inclusion: { in: ITEM_TYPES }
  validates :source_url, presence: true, uniqueness: true

  scope :featured, -> { where(featured: true) }
  scope :by_type, ->(type) { where(item_type: type) }

  translatable_fields :title, :subtitle
  rich_text_fields :body
end
