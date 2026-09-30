# A key for the public data API and the existing CMS draft-memo routes
# (docs/public-interface-design.md §4). One model for both: yfu_ keys from
# before the public API carry scopes ['cms:drafts'] and issuer 'local'.
#
# Issue, rotate and revoke keys through Keys::Issue, Keys::Rotate and
# Keys::Revoke; verify presented keys through Keys::Verify.
class ApiKey < ApplicationRecord
  SCOPES = {
    # People are included: person entities, individuals' names and roles.
    "read:public" => "Organizations, people, spending, documents, StatCan, releases, datasets and exports",
    "usage:read" => "Your own usage (/v1/me/usage)",
    "cms:drafts" => "Build Canada CMS draft-memo routes, acting as you"
  }.freeze
  # Not issued to keys: keys:manage is for OAuth tokens only, llm:* is reserved.
  RESERVED_SCOPES = %w[keys:manage llm:*].freeze
  DEFAULT_SCOPES = %w[read:public usage:read].freeze
  ANONYMOUS_SCOPES = %w[read:public].freeze

  GRACE_PERIODS = { "none" => 0, "1h" => 1.hour, "24h" => 24.hours, "7d" => 7.days }.freeze
  DEFAULT_GRACE_PERIOD = "24h".freeze
  EXPIRY_OPTIONS = { "30d" => 30.days, "90d" => 90.days, "365d" => 365.days, "never" => nil }.freeze
  DEFAULT_EXPIRY = "365d".freeze
  ISSUERS = %w[bifrost local].freeze
  # last_used_at is written at most once a minute per key, so verification
  # stays a read on the hot path.
  LAST_USED_RESOLUTION = 1.minute

  # Revoking deactivates the Bifrost virtual key inline; if Bifrost is down,
  # this job retries it (and Keys::ReconcileBifrostJob catches the rest).
  performs :deactivate_in_bifrost!, queue_as: :default do
    retry_on KeyIssuers::Unavailable, wait: :polynomially_longer, attempts: 10
  end

  # A failed edge push is retried here. The edge also re-fetches on a miss.
  performs :push_to_edge, queue_as: :default do
    retry_on Edge::Push::Error, wait: :polynomially_longer, attempts: 10
  end

  belongs_to :user
  belongs_to :account
  belongs_to :rotated_from, class_name: "ApiKey", optional: true
  has_one :rotated_to, class_name: "ApiKey", foreign_key: :rotated_from_id, inverse_of: :rotated_from, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validates :issuer, inclusion: { in: ISSUERS }
  validate :scopes_are_known
  validate :name_unique_among_live_keys
  validate :restrictions_are_valid

  normalizes :allowed_origins, with: ->(origins) { Array(origins).map { |o| o.to_s.strip.chomp("/").downcase }.compact_blank.uniq }
  normalizes :allowed_ips, with: ->(ips) { Array(ips).map { |ip| ip.to_s.strip }.compact_blank.uniq }
  normalizes :scopes, with: ->(scopes) { Array(scopes).map(&:to_s).compact_blank.uniq.sort }

  # Not revoked (the pre-public-API meaning of "active").
  scope :active, -> { where(revoked_at: nil) }
  # Usable right now, ignoring the account's suspension.
  scope :live, -> {
    now = Time.current
    where(revoked_at: nil)
      .where("api_keys.expires_at IS NULL OR api_keys.expires_at > ?", now)
      .where("api_keys.grace_until IS NULL OR api_keys.grace_until > ?", now)
  }
  scope :bifrost, -> { where(issuer: "bifrost") }

  class << self
    # Issues a local cms:drafts key for a user without calling Bifrost. For
    # tests and console use; the developer console goes through Keys::Issue.
    def issue!(user:, name:, scopes: [ "cms:drafts" ])
      result = Keys::Issue.call(
        account: Account.personal_for!(user),
        user:,
        name:,
        scopes:,
        expires_in: nil,
        issuer: KeyIssuers::LocalIssuer.new,
        context: AuditEvent::Context.system,
        enforce_limits: false
      )
      raise ActiveRecord::RecordInvalid, result.api_key unless result.ok?

      [ result.api_key, result.raw_key ]
    end

    # The CMS path: a key with cms:drafts, acting as its user. Returns nil
    # for any key that can't be used there.
    def authenticate(raw_token)
      result = Keys::Verify.call(raw_token, scopes: [ "cms:drafts" ])
      result.api_key if result.ok?
    end

    def find_by_raw(raw) = find_by(token_digest: ApiKey::Token.digest(raw))
  end

  def status(at = Time.current)
    return "revoked" if revoked_at?
    return "expired" if expires_at && expires_at <= at
    return "expired" if grace_until && grace_until <= at
    return "suspended" if account.suspended?
    return "rotating" if grace_until

    "active"
  end

  def usable?(at = Time.current) = status(at).in?(%w[active rotating])

  def scope?(scope) = scopes.include?(scope.to_s)

  def bifrost? = issuer == "bifrost"

  def legacy? = token_prefix.start_with?(ApiKey::Token::LEGACY_PREFIX)

  # Called by Keys::Verify after a successful verification. At most one
  # UPDATE per key per LAST_USED_RESOLUTION, conditional so concurrent
  # requests don't pile up writes.
  def record_use!(ip:, at: Time.current)
    return if last_used_at && last_used_at > at - LAST_USED_RESOLUTION

    ApiKey.where(id:)
      .where("last_used_at IS NULL OR last_used_at <= ?", at - LAST_USED_RESOLUTION)
      .update_all(last_used_at: at, last_used_ip: ip)
  end

  # The edge key lookup body (the WS-H contract in §14 WS-E):
  # GET /internal/keys/lookup and PUT {edge}/internal/keys/{digest}.
  def lookup_payload
    plan = account.plan_definition
    {
      key_id: id,
      account_id: account_id,
      plan: plan.name,
      scopes:,
      status:,
      expires_at: expires_at&.iso8601,
      grace_until: grace_until&.iso8601,
      allowed_origins:,
      allowed_ips:,
      limits: plan.limits
    }
  end

  def deactivate_in_bifrost! = KeyIssuers::BifrostIssuer.new.deactivate(self)

  def push_to_edge = Edge::Push.new.deliver!(self)

  def ip_allowed?(ip)
    return true if allowed_ips.empty?
    return false if ip.blank?

    address = IPAddr.new(ip)
    allowed_ips.any? { |range| IPAddr.new(range).include?(address) }
  rescue IPAddr::InvalidAddressError
    false
  end

  def origin_allowed?(origin)
    return true if allowed_origins.empty?

    origin.present? && allowed_origins.include?(origin.to_s.chomp("/").downcase)
  end

  private

  def scopes_are_known
    unknown = scopes - SCOPES.keys
    errors.add(:scopes, "include unknown or reserved scopes: #{unknown.join(', ')}") if unknown.any?
    errors.add(:scopes, "must include at least one scope") if scopes.empty?
  end

  def name_unique_among_live_keys
    return if name.blank? || account_id.blank? || revoked_at? || grace_until?

    clash = ApiKey.where(account_id:, name:, revoked_at: nil, grace_until: nil).where.not(id:)
    errors.add(:name, "is already used by another key") if clash.exists?
  end

  def restrictions_are_valid
    allowed_ips.each do |range|
      IPAddr.new(range)
    rescue IPAddr::InvalidAddressError
      errors.add(:allowed_ips, "has an invalid address or CIDR range: #{range}")
    end
    allowed_origins.each do |origin|
      uri = URI.parse(origin)
      errors.add(:allowed_origins, "must be an http(s) origin such as https://example.com: #{origin}") unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.path.blank?
    rescue URI::InvalidURIError
      errors.add(:allowed_origins, "must be an http(s) origin such as https://example.com: #{origin}")
    end
  end
end
