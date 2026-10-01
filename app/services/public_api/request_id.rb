require "securerandom"

module PublicApi
  # Request IDs in the contract's form, `req_` and a ULID (Meta.request_id).
  # Problems repeat the ID as `instance`, and it is sent as BC-Request-Id.
  module RequestId
    CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".freeze

    module_function

    def generate(now: Time.current)
      "req_#{ulid(now:)}"
    end

    def ulid(now: Time.current)
      value = ((now.to_r * 1000).to_i << 80) | SecureRandom.random_number(1 << 80)
      Array.new(26) { |i| CROCKFORD[(value >> (5 * (25 - i))) & 31] }.join
    end
  end
end
