class Tool < ApplicationRecord
  include Translatable, Publishable, HasLocalizedMarkdown

  extend Mobility
  translates :title, backend: :column

  extend FriendlyId
  friendly_id :title_en, use: :history
  validates :slug, presence: true, uniqueness: true

  has_localized_markdown :description
  has_one_attached :image

  validates :size, inclusion: { in: %w[small big], allow_nil: true }

  scope :featured, -> { where(featured: true) }
  scope :ordered, -> { order(:position) }

  translatable_fields :title
  markdown_fields :description

  def should_generate_new_friendly_id?
    false
  end
end
