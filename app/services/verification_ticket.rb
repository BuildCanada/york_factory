require "jwt"

class VerificationTicket
  TTL = 15.minutes
  ALGORITHM = "HS256"
  ALLOWED_KINDS = %w[endorsement critique].freeze

  class Error < StandardError; end
  class InvalidTicket < Error; end
  class WrongKind < Error; end
  class WrongMemo < Error; end

  IDENTITY_FIELDS = %w[sub name given_name family_name email email_verified picture].freeze

  def self.issue(payload, kind:, memo_slug:)
    raise ArgumentError, "invalid kind" unless ALLOWED_KINDS.include?(kind.to_s)
    identity = payload.slice(*IDENTITY_FIELDS)
    now = Time.current.to_i
    JWT.encode(
      identity.merge(
        "kind" => kind.to_s,
        "memo_slug" => memo_slug.to_s,
        "iat" => now,
        "exp" => now + TTL.to_i
      ),
      secret,
      ALGORITHM
    )
  end

  def self.decode(token, expected_kind:, expected_memo_slug:)
    payload, _header = JWT.decode(token, secret, true, algorithm: ALGORITHM, verify_iat: true)
    raise WrongKind, "ticket kind mismatch"   unless payload["kind"] == expected_kind.to_s
    raise WrongMemo, "ticket memo mismatch"   unless payload["memo_slug"] == expected_memo_slug.to_s
    payload
  rescue JWT::DecodeError => e
    raise InvalidTicket, e.message
  end

  def self.secret
    ENV.fetch("VERIFICATION_TICKET_SECRET", Rails.application.secret_key_base)
  end
end
