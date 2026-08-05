class Search::Source < ApplicationRecord
  STRATEGIES = %w[record_adapter rss atom sitemap listing url].freeze

  has_many :fetches,
    class_name: "Search::SourceFetch",
    foreign_key: :search_source_id,
    inverse_of: :source,
    dependent: :destroy
  has_many :media_articles,
    class_name: "Search::MediaArticle",
    foreign_key: :search_source_id,
    inverse_of: :source,
    dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :realm, presence: true, inclusion: { in: ->(_) { Search::Realms.keys } }
  validates :strategy, inclusion: { in: STRATEGIES }
  validates :cadence_seconds,
    numericality: { only_integer: true, greater_than_or_equal_to: 60 }
  validates :url, presence: true, unless: :record_adapter?
  validate :configuration_is_object

  scope :enabled, -> { where(enabled: true) }
  scope :due, ->(at = Time.current) { enabled.where(next_fetch_at: ..at) }

  def record_adapter?
    strategy == "record_adapter"
  end

  def schedule_next!(from: Time.current)
    update!(next_fetch_at: from + cadence_seconds.seconds)
  end

  private

  def configuration_is_object
    errors.add(:configuration, "must be an object") unless configuration.is_a?(Hash)
  end
end
