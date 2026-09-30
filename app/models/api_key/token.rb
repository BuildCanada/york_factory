require "openssl"
require "zlib"

# The public key format of docs/public-interface-design.md §4.3:
#
#   bc_live_<secret>_<crc6>
#
# <secret> is the issuer's secret (Bifrost's virtual key value minus
# "sk-bf-"), and <crc6> is the base62 CRC32 of everything before it, so a
# mistyped key fails without a database lookup. Only an HMAC of the whole
# key is stored, under a pepper that is its own secret (not secret_key_base)
# and is shared with the edge Worker.
module ApiKey::Token
  LIVE_PREFIX = "bc_live_".freeze
  STAGING_PREFIX = "bc_stg_".freeze
  PREFIXES = [ LIVE_PREFIX, STAGING_PREFIX ].freeze
  LEGACY_PREFIX = "yfu_".freeze
  DISPLAY_PREFIX_LENGTH = 12
  CHECKSUM_LENGTH = 6
  BASE62 = [ *"0".."9", *"A".."Z", *"a".."z" ].join.freeze
  SECRET_FORMAT = /\A[A-Za-z0-9-]{16,128}\z/

  class InvalidSecret < StandardError; end

  module_function

  # The prefix this deployment issues. Staging sets API_KEY_PREFIX=bc_stg_.
  def prefix
    configured = ENV["API_KEY_PREFIX"].presence || Rails.application.credentials.dig(:api_keys, :prefix)
    return configured if configured.present?

    Rails.env.production? ? LIVE_PREFIX : STAGING_PREFIX
  end

  def wrap(secret, prefix: self.prefix)
    raise InvalidSecret, "Issuer returned a secret in an unexpected format" unless secret.to_s.match?(SECRET_FORMAT)

    body = "#{prefix}#{secret}"
    "#{body}_#{checksum(body)}"
  end

  # True when the key has a known prefix and a matching checksum.
  def well_formed?(raw)
    return false unless raw.is_a?(String) && raw.bytesize <= 256

    prefix = PREFIXES.find { |candidate| raw.start_with?(candidate) }
    return false unless prefix

    body, separator, crc = raw.rpartition("_")
    return false if separator.empty? || body.length <= prefix.length
    return false unless body.delete_prefix(prefix).match?(SECRET_FORMAT)

    ActiveSupport::SecurityUtils.secure_compare(crc, checksum(body))
  end

  def legacy?(raw) = raw.is_a?(String) && raw.start_with?(LEGACY_PREFIX)

  def digest(raw) = OpenSSL::HMAC.hexdigest("SHA256", pepper, raw)

  # yfu_ keys were digested under secret_key_base. Both digests are accepted
  # for 90 days after this change; a key's digest moves to the pepper the first
  # time it is used.
  def legacy_digest(raw) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw)

  def display_prefix(raw) = raw.first(DISPLAY_PREFIX_LENGTH)

  def checksum(body)
    value = Zlib.crc32(body)
    encoded = +""
    while value.positive?
      value, remainder = value.divmod(62)
      encoded.prepend(BASE62[remainder])
    end
    encoded.rjust(CHECKSUM_LENGTH, "0")
  end

  # API_KEY_PEPPER in production (from the environment or credentials
  # api_keys.pepper). Elsewhere a key derived from secret_key_base stands in,
  # so development and test need no setup.
  def pepper
    configured = ENV["API_KEY_PEPPER"].presence || Rails.application.credentials.dig(:api_keys, :pepper)
    return configured if configured.present?
    raise KeyError, "API_KEY_PEPPER is not configured" if Rails.env.production?

    @development_pepper ||= Rails.application.key_generator.generate_key("api_key_pepper", 32).unpack1("H*")
  end
end
