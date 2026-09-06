class Poll < ApplicationRecord
  include Translatable, Publishable, HasLocalizedMarkdown, ValidatesSlugAvailability

  extend Mobility
  translates :title, backend: :column
  extend FriendlyId
  friendly_id :title_en, use: :history

  has_localized_markdown :body
  has_localized_markdown :appendix
  include PollPublication

  has_one_attached :seo_image
  has_one_attached :banner_image
  belongs_to :author, class_name: "TeamMember", optional: true

  validates :slug, presence: true, uniqueness: true
  scope :featured, -> { where(featured: true) }
  scope :search, ->(q) { where("title_en ILIKE ?", "%#{sanitize_sql_like(q)}%") }

  translatable_fields :title, :email_subject, :tweet
  markdown_fields :body, :appendix, :methodology, :news_release, :subscriber_email
  hash_fields :key_messages

  def should_generate_new_friendly_id? = false
end
