class Memo < ApplicationRecord
  include Feedable, Translatable, Publishable, HasLocalizedRichText

  extend Mobility
  translates :title, backend: :column

  extend FriendlyId
  friendly_id :title_en, use: :history

  has_localized_rich_text :body
  has_localized_rich_text :appendix
  has_localized_rich_text :supporters
  has_one_attached :seo_image
  belongs_to :author, class_name: "TeamMember", optional: true
  belongs_to :co_author, class_name: "TeamMember", optional: true

  CATEGORIES = %w[housing industry government-transformation digital-innovation nation-building immigration energy finance defence].freeze

  validates :slug, presence: true, uniqueness: true
  validates :category, inclusion: { in: CATEGORIES, allow_nil: true }

  scope :featured, -> { where(featured: true) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :search, ->(q) {
    sanitized = ActiveRecord::Base.sanitize_sql_like(q)
    where("title_en ILIKE :q", q: "%#{sanitized}%")
  }

  translatable_fields :title
  rich_text_fields :body, :appendix, :supporters
  hash_fields :key_messages

  def self.feed_type_label = "memo"
end
