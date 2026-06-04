require "openssl"
require "securerandom"

class Warehouse::ApiToken < Warehouse::Record
  SCOPES = %w[kpis:read kpis:write].freeze

  validates :name, presence: true, uniqueness: true
  validates :token_hash, presence: true, uniqueness: true
  validate :scopes_subset_of_allowed

  scope :active, -> { where(revoked_at: nil) }

  class << self
    def issue!(name:, scopes:)
      raw = "yfk_#{SecureRandom.urlsafe_base64(32)}"
      create!(name: name, scopes: scopes, token_hash: hash_token(raw))
      raw
    end

    def authenticate(raw_token)
      return nil if raw_token.blank?

      record = active.find_by(token_hash: hash_token(raw_token))
      record&.touch(:last_used_at)
      record
    end

    def hash_token(raw)
      OpenSSL::HMAC.hexdigest("SHA256", token_pepper, raw)
    end

    private

    def token_pepper
      Rails.application.secret_key_base
    end
  end

  def revoked?
    revoked_at.present?
  end

  def has_scope?(scope)
    scopes.include?(scope.to_s)
  end

  private

  def scopes_subset_of_allowed
    extra = (scopes || []) - SCOPES
    errors.add(:scopes, "contains unknown scopes: #{extra.join(', ')}") if extra.any?
  end
end
