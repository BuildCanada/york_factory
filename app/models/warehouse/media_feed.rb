require "uri"

class Warehouse::MediaFeed < Warehouse::Record
  LANGUAGES = %w[en fr].freeze
  STRATEGIES = %w[rss atom].freeze

  has_many :fetches,
    class_name: "Warehouse::MediaFeedFetch",
    foreign_key: :media_feed_id,
    inverse_of: :feed,
    dependent: :destroy
  has_many :media_articles,
    class_name: "Warehouse::MediaArticle",
    foreign_key: :media_feed_id,
    inverse_of: :feed,
    dependent: :restrict_with_error

  before_validation :apply_feed_defaults
  before_validation :normalize_feed_configuration
  before_save :reset_fetch_state_for_feed_change

  validates :publisher_name, presence: true
  validates :publisher_domain, presence: true
  validates :language, inclusion: { in: LANGUAGES }
  validates :strategy, inclusion: { in: STRATEGIES }
  validates :name, presence: true, uniqueness: true
  validates :cadence_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 60 }
  validates :url, presence: true, uniqueness: { case_sensitive: false }
  validate :url_is_http
  validate :fallback_url_is_https
  validate :publisher_domain_is_valid

  scope :alphabetical, -> { order(:name, :id) }
  scope :enabled, -> { where(enabled: true) }
  scope :due, ->(at = Time.current) { enabled.where(next_fetch_at: ..at) }

  class << self
    def publishers
      all.filter_map(&:publisher).uniq { |publisher| publisher.fetch("domain") }
        .sort_by { |publisher| publisher.fetch("name") }
    end

    def publisher_for(host, feed: nil)
      normalized_host = normalize_host(host)
      return if normalized_host.blank?

      candidates = [ feed ].compact
      candidates.concat(all.to_a) unless feed
      matched_feed = candidates.find do |candidate|
        domain = normalize_host(candidate.publisher_domain)
        domain.present? && (normalized_host == domain || normalized_host.end_with?(".#{domain}"))
      end
      return unless matched_feed

      {
        "name" => matched_feed.publisher_name,
        "domain" => normalize_host(matched_feed.publisher_domain)
      }
    end

    def normalize_host(host)
      host.to_s.downcase.delete_suffix(".").delete_prefix("www.").presence
    end
  end

  def publisher
    return if publisher_name.blank? || publisher_domain.blank?

    { "name" => publisher_name, "domain" => publisher_domain }
  end

  def schedule_next!(from: Time.current)
    update!(next_fetch_at: from + cadence_seconds.seconds)
  end

  private

  def apply_feed_defaults
    self.strategy ||= "rss"
    self.language ||= "en"
    self.cadence_seconds ||= 300
    self.next_fetch_at ||= Time.current if enabled?
  end

  def normalize_feed_configuration
    self.publisher_name = publisher_name.to_s.squish.presence
    self.publisher_domain = self.class.normalize_host(publisher_domain)
    self.language = language.to_s.downcase.presence
    self.fallback_url = nil if fallback_url.blank?
  end

  def url_is_http
    return if valid_http_url?(url, allow_http:)

    errors.add(:url, "must use #{allow_http ? 'HTTP or HTTPS' : 'HTTPS'}")
  rescue URI::InvalidURIError
    errors.add(:url, "is invalid")
  end

  def fallback_url_is_https
    return if fallback_url.blank? || valid_http_url?(fallback_url, allow_http: false)

    errors.add(:fallback_url, "must use HTTPS")
  rescue URI::InvalidURIError
    errors.add(:fallback_url, "is invalid")
  end

  def publisher_domain_is_valid
    return if publisher_domain.blank?

    uri = URI.parse("https://#{publisher_domain}")
    errors.add(:publisher_domain, "is invalid") unless uri.host == publisher_domain && publisher_domain.include?(".")
  rescue URI::InvalidURIError
    errors.add(:publisher_domain, "is invalid")
  end

  def valid_http_url?(value, allow_http:)
    uri = URI.parse(value.to_s)
    schemes = allow_http ? %w[http https] : %w[https]
    uri.host.present? && uri.scheme.in?(schemes)
  end

  def reset_fetch_state_for_feed_change
    if will_save_change_to_url?
      self.etag = nil
      self.last_modified = nil
      self.consecutive_failures = 0
      self.next_fetch_at = Time.current if enabled?
    elsif will_save_change_to_enabled? && enabled?
      self.next_fetch_at = Time.current
    end
  end
end
