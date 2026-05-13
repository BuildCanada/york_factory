class Memo < ApplicationRecord
  include Feedable, Translatable, Publishable, HasLocalizedMarkdown

  extend Mobility
  translates :title, backend: :column

  extend FriendlyId
  friendly_id :title_en, use: :history

  has_localized_markdown :body
  has_localized_markdown :appendix
  has_localized_markdown :supporters
  has_one_attached :seo_image
  has_one_attached :banner_image
  belongs_to :author, class_name: "TeamMember", optional: true
  belongs_to :co_author, class_name: "TeamMember", optional: true

  CATEGORIES = %w[housing industry government-transformation digital-innovation nation-building immigration energy finance defence].freeze
  PUBLICATIONS = %w[build_toronto].freeze

  validates :slug, presence: true, uniqueness: { scope: :publication }
  validates :category, inclusion: { in: CATEGORIES, allow_nil: true }
  validates :publication, inclusion: { in: PUBLICATIONS, allow_blank: true }

  before_validation { self.publication = nil if publication.blank? }

  scope :featured, -> { where(featured: true) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :without_publication, -> { where(publication: nil) }
  scope :by_publication, ->(name) { where(publication: name) }
  scope :search, ->(q) {
    sanitized = ActiveRecord::Base.sanitize_sql_like(q)
    where("title_en ILIKE :q", q: "%#{sanitized}%")
  }

  translatable_fields :title
  markdown_fields :body, :appendix, :supporters
  hash_fields :key_messages

  def self.feed_type_label = "memo"

  def should_generate_new_friendly_id?
    false
  end

  private

  def should_appear_in_feed?
    publication.blank? && super
  end
end
