class Search::MediaArticle < ApplicationRecord
  include Searchable

  searchable_in realm: "media", record_type: "article"

  STATES = %w[draft published withdrawn invalid].freeze
  LANGUAGES = %w[en fr und].freeze
  VISIBILITIES = %w[public].freeze

  belongs_to :source,
    class_name: "Search::Source",
    foreign_key: :search_source_id,
    inverse_of: :media_articles,
    optional: true

  before_validation :normalize_envelope

  validates :state, inclusion: { in: STATES }
  validates :language, inclusion: { in: LANGUAGES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :search_revision, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :search_embedding_scope, inclusion: { in: %w[full truncated] }, allow_nil: true
  validate :source_is_media
  validate :realm_contract_accepts_article

  scope :published, -> { where(state: "published") }
  scope :search_indexable, -> { published }
  scope :search_synced, -> { where.not(search_synced_at: nil) }

  ImportResult = Data.define(:article, :changed)

  def self.import!(source:, feed_entry:, extraction:, normalizer: Search::Media::ArticleNormalizer.new)
    attempts = 0
    begin
      attributes = normalizer.call(source:, feed_entry:, extraction:)
      article = find_or_initialize_by(
        canonical_url_digest: Digest::SHA256.hexdigest(attributes.fetch(:canonical_url))
      )
      attributes = attributes.except(:search_source_id) if article.persisted?
      previous_revision = article.search_revision.to_i
      article.assign_attributes(attributes)
      article.first_seen_at ||= Time.current
      article.last_seen_at = Time.current
      article.publish!
      ImportResult.new(article:, changed: article.search_revision.to_i > previous_revision)
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts == 1
      raise
    end
  end

  def realm
    "media"
  end

  def record_type
    "article"
  end

  def realm_contract
    Search::Realms.fetch(realm)
  end

  def search_data
    {
      state: state,
      language: language,
      visibility: visibility,
      permission_ids: permission_ids,
      title: title,
      summary: summary,
      content: content,
      canonical_url: canonical_url,
      source_url: source_url,
      source_name: source&.name,
      published_at: published_at,
      source_updated_at: source_updated_at,
      first_seen_at: first_seen_at,
      last_seen_at: last_seen_at,
      ontology: ontology,
      realm_data: realm_data
    }.compact
  end

  def publish!(seen_at: Time.current)
    transaction do
      normalize_envelope
      self.state = "published"
      self.first_seen_at ||= seen_at
      self.last_seen_at = seen_at
      next_hash = realm_contract.content_hash(self)

      if persisted? && search_content_hash == next_hash && !new_material_changes?
        update_columns(last_seen_at: seen_at, updated_at: seen_at)
        return self
      end

      self.search_content_hash = next_hash
      self.search_revision += 1
      self.validation_errors = []
      save!
    end
    self
  rescue ActiveRecord::RecordInvalid => error
    self.validation_errors = error.record.errors.to_hash(true)
    raise
  end

  def withdraw!
    transaction do
      self.state = "withdrawn"
      self.search_revision += 1
      save!
    end
    self
  end

  private

  def normalize_envelope
    self.language = language.to_s.downcase.presence || "und"
    self.title = title.to_s.strip.presence
    self.summary = summary.to_s.strip.presence
    self.content = content.to_s.strip.presence
    self.canonical_url = canonical_url.to_s.strip.presence
    self.source_url = source_url.to_s.strip.presence
    self.canonical_url_digest = Digest::SHA256.hexdigest(canonical_url) if canonical_url
    self.ontology = {} unless ontology.is_a?(Hash)
    self.realm_data = {} unless realm_data.is_a?(Hash)
  end

  def source_is_media
    return unless source && source.realm != realm

    errors.add(:source, "must belong to the media realm")
  end

  def realm_contract_accepts_article
    realm_contract.validate_document(self).each do |message|
      errors.add(:realm_data, message)
    end
  end

  def new_material_changes?
    material_attributes = %w[
      state visibility permission_ids canonical_url source_url title summary content
      language published_at source_updated_at ontology realm_data
    ]
    (changes_to_save.keys & material_attributes).any?
  end
end
