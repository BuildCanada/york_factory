module PublicApi
  # How the API writes values (docs/openapi/public/v1/DECISIONS.md 12 to 15):
  # gids, money as decimal strings, fiscal year labels, RFC 3339 timestamps.
  module Format
    GID = "gid://buildcanada".freeze
    ULID = /\A[0-9A-HJKMNP-TV-Z]{26}\z/
    PARTIAL_DATE = /\A[0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?\z/
    SHA256 = /\A[0-9a-f]{64}\z/

    module_function

    def gid(type, key) = key.nil? ? nil : "#{GID}/#{type}/#{key}"

    def entity_gid(entity_id) = gid("Entity", entity_id)

    # A path or filter ID: the bare key, or its gid (already percent-decoded).
    def bare_id(value, type)
      value.to_s.delete_prefix("#{GID}/#{type}/")
    end

    # "125000.00": at least 2 and at most 6 decimals (Amount).
    def amount(value)
      return nil if value.nil?

      decimal = BigDecimal(value.to_s).round(6)
      whole, fraction = decimal.to_s("F").split(".")
      fraction = fraction.to_s.sub(/0+\z/, "").ljust(2, "0")
      "#{whole}.#{fraction}"
    end

    # 2024 -> "2024-25".
    def fiscal_year(start_year)
      return nil if start_year.nil?

      "#{start_year}-#{format('%02d', (start_year.to_i + 1) % 100)}"
    end

    # "2024-25" -> 2024, or nil when the label is inconsistent ("2024-26").
    def fiscal_year_start(label)
      match = /\A(\d{4})-(\d{2})\z/.match(label.to_s) or return nil
      start = match[1].to_i
      start if format("%02d", (start + 1) % 100) == match[2]
    end

    def timestamp(value)
      return nil if value.nil?

      time = value.is_a?(Numeric) ? Time.at(value) : value.to_time
      time.utc.iso8601
    end

    def partial_date(value)
      value.to_s.match?(PARTIAL_DATE) ? value.to_s : nil
    end

    def sha256(value)
      value.to_s.match?(SHA256) ? value.to_s : nil
    end
  end
end
