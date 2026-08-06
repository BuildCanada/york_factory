module Search
  module Schema
    module_function

    VERSION = 1
    MAX_ID_BYTES = 64
    MAX_FILTERABLE_STRING_BYTES = 16_384

    class ValidationError < StandardError; end

    def document
      @document ||= Search::Realms.keys.each_with_object({}) do |realm, union|
        Search::Realms.fetch(realm).turbopuffer_schema.each do |name, configuration|
          name = name.to_sym
          existing = union[name]
          if existing && existing != configuration
            raise "conflicting Turbopuffer schema for #{name}: #{existing.inspect} != #{configuration.inspect}"
          end
          union[name] = configuration
        end
      end.freeze
    end

    def digest
      Search::CanonicalJson.digest(document)
    end

    def reset!
      @document = nil
    end

    def normalize_and_validate!(row, schema: document, required: [])
      raise ValidationError, "search data must be a hash" unless row.is_a?(Hash)

      schema = schema.to_h.transform_keys(&:to_sym)
      normalized = row.to_h.each_with_object({}) do |(name, value), result|
        name = name.to_sym
        result[name] = normalize_value(value, schema[name])
      end
      validate_id!(normalized[:id])
      unknown = normalized.keys - schema.keys - [ :id ]
      if unknown.any?
        raise ValidationError, "search data contains unknown attributes: #{unknown.sort.join(', ')}"
      end

      schema.each do |name, configuration|
        value = normalized[name]
        validate_flat_value!(name, value)
        validate_type!(name, value, schema_type(configuration)) unless value.nil?
        validate_filterable_string_size!(name, value, configuration)
      end
      missing = required.select { |name| normalized[name].nil? }
      if missing.any?
        raise ValidationError, "search data is missing required attributes: #{missing.join(', ')}"
      end
      unless normalized[:index_sequence].is_a?(Integer) && normalized[:index_sequence].positive?
        raise ValidationError, "index_sequence must be a positive integer"
      end
      unless normalized[:search_revision].is_a?(Integer) && normalized[:search_revision].positive?
        raise ValidationError, "search_revision must be a positive integer"
      end
      normalized
    end

    def normalize_value(value, configuration)
      return value unless schema_type(configuration).to_s == "datetime"
      return value if value.nil? || value.is_a?(String)
      return value.to_time.utc.iso8601(6) if value.respond_to?(:to_time)

      value
    end
    private_class_method :normalize_value

    def validate_id!(id)
      unless id.present? && id.bytesize <= MAX_ID_BYTES
        raise ValidationError, "document id must be between 1 and #{MAX_ID_BYTES} bytes"
      end
    end
    private_class_method :validate_id!

    def validate_flat_value!(name, value)
      valid = value.nil? || scalar?(value) || (value.is_a?(Array) && value.all? { |item| scalar?(item) })
      raise ValidationError, "#{name} must be a scalar or an array of scalars" unless valid
    end
    private_class_method :validate_flat_value!

    def scalar?(value)
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false ||
        value.is_a?(Time) || value.is_a?(Date) || value.is_a?(DateTime)
    end
    private_class_method :scalar?

    def schema_type(configuration)
      configuration.is_a?(Hash) ? (configuration[:type] || configuration["type"]) : configuration
    end
    private_class_method :schema_type

    def validate_type!(name, value, type)
      return if type.blank?

      valid = case type.to_s
      when "string", "uuid", "datetime"
        value.is_a?(String) || (type.to_s == "datetime" && value.respond_to?(:iso8601))
      when "uint"
        value.is_a?(Integer) && value >= 0
      when "int"
        value.is_a?(Integer)
      when "float"
        value.is_a?(Numeric) && value.finite?
      when "bool"
        value == true || value == false
      when /\A\[\](.+)\z/
        value.is_a?(Array) && value.all? { |item| type_matches_scalar?(item, Regexp.last_match(1)) }
      when /\A\[(\d+)\]f(?:16|32)\z/
        value.is_a?(Array) && value.length == Regexp.last_match(1).to_i &&
          value.all? { |item| item.is_a?(Numeric) && item.finite? }
      else
        false
      end
      raise ValidationError, "#{name} does not match Turbopuffer type #{type}" unless valid
    end
    private_class_method :validate_type!

    def type_matches_scalar?(value, type)
      case type
      when "string", "uuid" then value.is_a?(String)
      when "uint" then value.is_a?(Integer) && value >= 0
      when "int" then value.is_a?(Integer)
      when "float" then value.is_a?(Numeric) && value.finite?
      when "bool" then value == true || value == false
      else false
      end
    end
    private_class_method :type_matches_scalar?

    def validate_filterable_string_size!(name, value, configuration)
      return unless filterable?(configuration)

      strings = value.is_a?(Array) ? value.grep(String) : Array(value).grep(String)
      return unless strings.any? { |string| string.bytesize > MAX_FILTERABLE_STRING_BYTES }

      raise ValidationError, "#{name} exceeds the filterable string size limit"
    end
    private_class_method :validate_filterable_string_size!

    def filterable?(configuration)
      return true unless configuration.is_a?(Hash)
      return configuration[:filterable] if configuration.key?(:filterable)
      return configuration["filterable"] if configuration.key?("filterable")
      return false if configuration[:full_text_search] || configuration["full_text_search"] ||
        configuration[:regex] || configuration["regex"]

      true
    end
    private_class_method :filterable?
  end
end
