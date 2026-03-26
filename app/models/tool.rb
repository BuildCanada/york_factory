class Tool < ApplicationRecord
  include Translatable, Publishable, HasLocalizedRichText

  extend Mobility
  translates :title, backend: :column

  extend FriendlyId
  friendly_id :title_en, use: :history

  has_localized_rich_text :description
  has_one_attached :image

  validates :size, inclusion: { in: %w[small big], allow_nil: true }

  scope :featured, -> { where(featured: true) }
  scope :ordered, -> { order(:position) }

  translatable_fields :title
  rich_text_fields :description
end
