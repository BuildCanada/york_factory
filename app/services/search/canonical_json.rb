require "json"

module Search
  module CanonicalJson
    module_function

    def normalize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), result|
          result[key.to_s] = normalize(child)
        end.sort.to_h
      when Array
        value.map { |child| normalize(child) }
      when Time, DateTime, ActiveSupport::TimeWithZone
        value.iso8601(6)
      when Date
        value.iso8601
      when BigDecimal
        value.to_s("F")
      else
        value
      end
    end

    def dump(value)
      JSON.generate(normalize(value))
    end

    def digest(value)
      Digest::SHA256.hexdigest(dump(value))
    end
  end
end
