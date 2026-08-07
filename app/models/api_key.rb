require "openssl"
require "securerandom"

class ApiKey < ApplicationRecord
  TOKEN_PREFIX = "yfu_".freeze

  belongs_to :user

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true

  scope :active, -> { where(revoked_at: nil) }

  class << self
    def issue!(user:, name:)
      raw_token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
      api_key = create!(
        user:,
        name:,
        token_digest: digest(raw_token),
        token_prefix: raw_token.first(12)
      )

      [ api_key, raw_token ]
    end

    def authenticate(raw_token)
      return if raw_token.blank? || !raw_token.start_with?(TOKEN_PREFIX)

      api_key = active.includes(:user).find_by(token_digest: digest(raw_token))
      api_key&.touch(:last_used_at)
      api_key
    end

    private

    def digest(raw_token)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw_token)
    end
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
