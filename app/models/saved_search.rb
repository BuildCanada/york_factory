class SavedSearch < ApplicationRecord
  START_POLICIES = %w[future_only backfill].freeze
  DELIVERY_MODES = %w[instant digest].freeze

  belongs_to :user
  has_many :runs, class_name: "SavedSearchRun", dependent: :destroy
  has_many :matches, class_name: "SavedSearchMatch", dependent: :destroy
  has_many :notification_batches, dependent: :destroy

  before_validation :normalize_definition
  before_validation :reset_run_schedule

  validates :name, presence: true
  validates :realm, presence: true, inclusion: { in: ->(_) { Search::Realms.keys } }
  validates :definition_digest, presence: true
  validates :definition_version,
    numericality: { only_integer: true, greater_than: 0 }
  validates :poll_interval_seconds,
    numericality: { only_integer: true, in: 60..86_400 }
  validates :cursor_sequence,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :start_policy, inclusion: { in: START_POLICIES }
  validates :delivery_mode, inclusion: { in: DELIVERY_MODES }
  validate :realm_accepts_definition
  validate :valid_delivery_configuration
  validate :valid_timezone

  scope :enabled, -> { where(enabled: true) }
  scope :due, ->(at = Time.current) { enabled.where(next_run_at: ..at) }

  def realm_contract
    Search::Realms.fetch(realm)
  end

  def schedule_next!(from: Time.current)
    update!(next_run_at: from + poll_interval_seconds.seconds)
  end

  def material_definition_changed?
    will_save_change_to_definition_digest? && persisted?
  end

  private

  def reset_run_schedule
    return unless enabled?
    return unless new_record? || will_save_change_to_enabled? ||
      will_save_change_to_poll_interval_seconds? || will_save_change_to_definition_digest?

    self.next_run_at = Time.current
  end

  def normalize_definition
    self.definition = {} unless definition.is_a?(Hash)
    normalized = Search::CanonicalJson.normalize(definition.deep_stringify_keys)
    normalized["version"] ||= 1
    normalized["realm"] ||= realm
    self.definition = normalized
    self.realm ||= normalized["realm"].to_s.presence
    self.definition_digest = Search::CanonicalJson.digest(normalized)
  end

  def realm_accepts_definition
    return unless Search::Realms.key?(realm)

    realm_contract.validate_definition(definition).each do |message|
      errors.add(:definition, message)
    end
  end

  def valid_delivery_configuration
    unless delivery_configuration.is_a?(Hash)
      errors.add(:delivery_configuration, "must be an object")
      return
    end

    channels = Array(delivery_configuration["channels"] || delivery_configuration[:channels])
    errors.add(:delivery_configuration, "must include email") unless channels.include?("email")
    if (channels - %w[email]).any?
      errors.add(:delivery_configuration, "contains an unsupported channel")
    end
  end

  def valid_timezone
    errors.add(:timezone, "is not a recognized IANA timezone") unless ActiveSupport::TimeZone[timezone]
  end
end
