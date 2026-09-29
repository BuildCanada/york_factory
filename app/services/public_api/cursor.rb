require "openssl"

module PublicApi
  # Opaque, signed pagination cursors (docs/public-interface-design.md §3.1):
  # `c1.<base64url JSON>.<base64url HMAC>`. The JSON holds the release the page
  # was read from (`r`), the sort key and last ID of the page (`k`), and a
  # fingerprint of the request's other parameters (`f`), so a cursor sent with
  # different filters is refused instead of returning a wrong page. A cursor
  # never expires: it names its release, and releases are immutable.
  module Cursor
    VERSION = "c1".freeze

    Decoded = Data.define(:release, :keys, :fingerprint)

    class Invalid < StandardError; end

    module_function

    def encode(release:, keys:, fingerprint:)
      payload = Base64.urlsafe_encode64({ r: release, k: keys, f: fingerprint }.to_json, padding: false)
      [ VERSION, payload, sign(payload) ].join(".")
    end

    def decode(value)
      version, payload, signature = value.to_s.split(".", 3)
      raise Invalid, "not a cursor from this API" unless version == VERSION && payload.present? && signature.present?
      raise Invalid, "the cursor's signature does not match" unless ActiveSupport::SecurityUtils.secure_compare(sign(payload), signature)

      data = JSON.parse(Base64.urlsafe_decode64(payload))
      raise Invalid, "not a cursor from this API" unless data.is_a?(Hash) && data["k"].is_a?(Array)

      Decoded.new(release: data["r"], keys: data["k"], fingerprint: data["f"])
    rescue ArgumentError, JSON::ParserError
      raise Invalid, "not a cursor from this API"
    end

    # A short digest of the parameters a cursor must be sent with again.
    def fingerprint(params)
      canonical = params.to_h.transform_keys(&:to_s).sort.to_h.to_json
      OpenSSL::Digest::SHA256.hexdigest(canonical)[0, 16]
    end

    def sign(payload)
      Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", secret, payload), padding: false)[0, 22]
    end

    def secret
      @secret ||= Rails.application.key_generator.generate_key("public_api/v1 cursor", 32)
    end
  end
end
