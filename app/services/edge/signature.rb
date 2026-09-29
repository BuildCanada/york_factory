require "openssl"

module Edge
  # HMAC signing for Rails <-> Worker internal calls:
  #
  #   BC-Edge-Timestamp: <unix seconds>
  #   BC-Edge-Signature: v1=<hex HMAC-SHA256(secret, "<ts>\n<METHOD>\n<path?query>\n<hex sha256(body)>")>
  #
  # A signature is accepted within WINDOW seconds of its timestamp. The
  # secret is EDGE_HMAC_SECRET (or credentials edge.hmac_secret), shared with
  # the Worker and separate from API_KEY_PEPPER.
  module Signature
    WINDOW = 60
    TIMESTAMP_HEADER = "BC-Edge-Timestamp".freeze
    SIGNATURE_HEADER = "BC-Edge-Signature".freeze

    module_function

    def headers(method:, path:, body: "", secret: Edge.secret, now: Time.current)
      timestamp = now.to_i.to_s
      { TIMESTAMP_HEADER => timestamp, SIGNATURE_HEADER => "v1=#{sign(secret, timestamp, method, path, body)}" }
    end

    def valid?(method:, path:, body:, timestamp:, signature:, secret: Edge.secret, now: Time.current)
      return false if secret.blank? || timestamp.blank? || signature.blank?
      return false unless timestamp.to_s.match?(/\A\d+\z/)
      return false if (now.to_i - timestamp.to_i).abs > WINDOW

      expected = "v1=#{sign(secret, timestamp.to_s, method, path, body)}"
      ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
    end

    def sign(secret, timestamp, method, path, body)
      payload = [ timestamp, method.to_s.upcase, path, OpenSSL::Digest::SHA256.hexdigest(body.to_s) ].join("\n")
      OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
    end
  end
end
