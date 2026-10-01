module PublicApi
  # Parses and checks a request's parameters against its operation in the
  # contract: unknown query parameters are refused ("documented filters only",
  # docs/public-interface-design.md §3.1), each value is coerced by its schema
  # type (comma-separated lists, integers, booleans) and validated with the
  # parameter's own JSON Schema. Every rejected parameter is reported at once,
  # as a 400 invalid_parameter problem.
  class Parameters
    HINTS = {
      "fiscal_year" => "Use YYYY-YY, e.g. 2024-25",
      "as_of" => "Use a revision number (31), a snapshot name (release-14), a date (2026-10-01) or an RFC 3339 timestamp (2026-10-01T03:00:00Z).",
      "amount_min" => "Use a decimal string with 2 to 6 decimals, e.g. 125000.00",
      "amount_max" => "Use a decimal string with 2 to 6 decimals, e.g. 125000.00",
      "id" => "Use the 26-character ID or its percent-encoded gid.",
      "payer" => "Use an entity's 26-character ID or its gid.",
      "recipient" => "Use an entity's 26-character ID or its gid."
    }.freeze

    attr_reader :values

    def self.parse(operation, query:, path:) = new(operation, query:, path:).tap(&:parse!)

    def initialize(operation, query:, path:)
      @operation = operation
      @query = query.to_h.transform_keys(&:to_s)
      @path = path.to_h.transform_keys(&:to_s)
      @values = {}
      @errors = []
    end

    def [](name) = @values[name.to_s]

    def key?(name) = @values.key?(name.to_s)

    # The query parameters as the caller sent them, in their order, for links.
    def sent = @query

    def parse!
      known = @operation.query_parameters.map(&:name)
      (@query.keys - known).each do |name|
        @errors << { parameter: name, detail: "Unknown parameter. This operation takes #{known.any? ? known.join(', ') : 'no query parameters'}." }
      end
      @operation.parameters.each { |param| parse_one(param) }
      raise Problem.invalid(@errors) if @errors.any?

      self
    end

    private

    def parse_one(param)
      raw = case param.location
      when "query" then @query[param.name]
      when "path" then @path[param.name]
      else return
      end
      if raw.nil?
        @errors << { parameter: param.name, detail: "Required." } if param.required
        default = param.schema["default"]
        @values[param.name] = default unless default.nil?
        return
      end
      if raw.is_a?(Array) || raw.is_a?(Hash)
        return @errors << { parameter: param.name, detail: "Send the parameter once; separate list values with commas." }
      end

      value = coerce(param, raw)
      return if value.equal?(INVALID)

      error = Spec.schema_at(param.schema_pointer).validate(value).first
      error ||= { "schema" => {} } if param.name == "fiscal_year" && Format.fiscal_year_start(value).nil?
      if error
        @errors << { parameter: param.name, detail: hint(param, error) }
      else
        @values[param.name] = value
      end
    end

    INVALID = Object.new.freeze

    def coerce(param, raw)
      case param.type
      when "integer"
        return Integer(raw, 10) if raw.match?(/\A-?\d+\z/)

        @errors << { parameter: param.name, detail: "Must be a whole number." }
        INVALID
      when "boolean"
        return raw == "true" if %w[true false].include?(raw)

        @errors << { parameter: param.name, detail: "Must be true or false." }
        INVALID
      when "array"
        raw.split(",", -1).map(&:strip)
      else
        raw
      end
    end

    def hint(param, error)
      return HINTS[param.name] if HINTS.key?(param.name)

      schema = error["schema"].is_a?(Hash) ? error["schema"] : {}
      if schema["enum"]
        "Must be one of #{schema['enum'].compact.join(', ')}."
      elsif schema.key?("minimum") || schema.key?("maximum")
        "Must be between #{schema['minimum'] || 'any'} and #{schema['maximum'] || 'any'}."
      elsif schema.key?("minLength") || schema.key?("maxLength")
        "Must have #{schema['minLength'] || 0} to #{schema['maxLength'] || 'any'} characters."
      elsif param.example
        "Invalid value. For example: #{Array(param.example).join(',')}."
      else
        "Invalid value."
      end
    end
  end
end
