require "uri"

module Search
  module Realms
    class Base
      VERSION = 1
      EMBEDDING_MODEL = "embed-v-4-0"
      EMBEDDING_DIMENSIONS = 1_024
      MODES = %w[filter_only lexical semantic hybrid].freeze
      COMMON_FILTER_FIELDS = {
        "record_type" => %w[eq in],
        "language" => %w[eq in],
        "published_at" => %w[eq gt gte lt lte],
        "source_updated_at" => %w[eq gt gte lt lte],
        "jurisdiction_ids" => %w[contains_any contains_all],
        "jurisdiction_codes" => %w[contains_any contains_all],
        "jurisdiction_levels" => %w[contains_any contains_all],
        "organization_ids" => %w[contains_any contains_all],
        "geo_boundary_ids" => %w[contains_any contains_all],
        "province_codes" => %w[contains_any contains_all],
        "country_codes" => %w[contains_any contains_all],
        "tags" => %w[contains_any contains_all],
        "categories" => %w[contains_any contains_all]
      }.freeze
      COMMON_SCHEMA = {
        realm: { type: "string", filterable: true },
        record_type: { type: "string", filterable: true },
        language: { type: "string", filterable: true },
        visibility: { type: "string", filterable: true },
        permission_ids: { type: "[]uuid", filterable: true },
        index_sequence: { type: "uint", filterable: true },
        search_revision: { type: "uint", filterable: true },
        search_content_hash: { type: "string", filterable: false },
        title: { type: "string", filterable: false },
        title_en: { type: "string", full_text_search: true },
        content_en: { type: "string", full_text_search: true },
        title_fr: { type: "string", full_text_search: true },
        content_fr: { type: "string", full_text_search: true },
        summary: { type: "string", filterable: false },
        canonical_url: { type: "string", filterable: false },
        source_url: { type: "string", filterable: false },
        source_name: { type: "string", filterable: true },
        source_domain: { type: "string", filterable: true },
        published_at: { type: "datetime", filterable: true },
        source_updated_at: { type: "datetime", filterable: true },
        first_seen_at: { type: "datetime", filterable: true },
        last_seen_at: { type: "datetime", filterable: true },
        jurisdiction_ids: { type: "[]uint", filterable: true },
        jurisdiction_codes: { type: "[]string", filterable: true },
        jurisdiction_levels: { type: "[]string", filterable: true },
        organization_ids: { type: "[]uint", filterable: true },
        organization_names: { type: "[]string", filterable: false },
        geo_boundary_ids: { type: "[]uint", filterable: true },
        province_codes: { type: "[]string", filterable: true },
        country_codes: { type: "[]string", filterable: true },
        tags: { type: "[]string", filterable: true },
        categories: { type: "[]string", filterable: true },
        embedding: { type: "[1024]f16", ann: true },
        embedding_model: { type: "string", filterable: false },
        embedding_scope: { type: "string", filterable: false },
        embedding_input_tokens: { type: "uint", filterable: false }
      }.freeze

      class << self
        def version
          self::VERSION
        end

        def realm_key
          Search::Realms::REGISTRY.key(name)
        end

        def allowed_record_types
          self::RECORD_TYPES
        end

        def field_types
          self::FIELD_TYPES
        end

        def required_fields
          self::REQUIRED_FIELDS
        end

        def filter_fields
          COMMON_FILTER_FIELDS.merge(self::FILTER_FIELDS)
        end

        def facet_fields
          self::FACET_FIELDS
        end

        def turbopuffer_schema
          COMMON_SCHEMA.merge(self::TURBOPUFFER_SCHEMA)
        end

        def embedding_fields
          const_defined?(:EMBEDDING_FIELDS, false) ? self::EMBEDDING_FIELDS : []
        end

        def validate_document(document)
          record_type = document_attribute(document, :record_type)
          state = document_attribute(document, :state) || "published"
          title = document_attribute(document, :title)
          content = document_attribute(document, :content)
          errors = []
          errors << "record_type is not supported" unless allowed_record_types.include?(record_type)
          errors << "title is required for publication" if state == "published" && title.blank?
          errors << "content is required for publication" if state == "published" && content.blank?
          data = document_attribute(document, :realm_data)
          return errors << "must be an object" unless data.is_a?(Hash)

          data = data.stringify_keys
          unknown = data.keys - field_types.keys
          errors << "contains unknown fields: #{unknown.sort.join(', ')}" if unknown.any?
          required_fields.each do |field|
            errors << "#{field} is required" if data[field].nil? || data[field].respond_to?(:empty?) && data[field].empty?
          end
          field_types.each do |field, type|
            value = data[field]
            next if value.nil? || valid_type?(value, type)

            errors << "#{field} must be #{type}"
          end
          errors.concat(validate_realm_data(data, document))
          errors
        end

        def validate_realm_data(_data, _document)
          []
        end

        def content_hash(document)
          Search::CanonicalJson.digest(
            realm: document_attribute(document, :realm),
            record_type: document_attribute(document, :record_type),
            visibility: document_attribute(document, :visibility),
            canonical_url: document_attribute(document, :canonical_url),
            source_url: document_attribute(document, :source_url),
            title: document_attribute(document, :title),
            summary: document_attribute(document, :summary),
            content: document_attribute(document, :content),
            language: document_attribute(document, :language),
            published_at: document_attribute(document, :published_at),
            source_updated_at: document_attribute(document, :source_updated_at),
            ontology: document_attribute(document, :ontology),
            realm_data: document_attribute(document, :realm_data)
          )
        end

        def validate_definition(definition)
          DefinitionValidator.new(self, definition).errors
        end

        private

        def document_attribute(document, name)
          if document.is_a?(Hash)
            document.key?(name) ? document[name] : document[name.to_s]
          else
            document.public_send(name)
          end
        end

        def valid_type?(value, type)
          case type
          when :string then value.is_a?(String)
          when :integer then value.is_a?(Integer) && value >= 0
          when :number then value.is_a?(Numeric) && value.finite?
          when :boolean then value == true || value == false
          when :datetime then value.is_a?(String) || value.respond_to?(:iso8601)
          when :string_array then value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
          when :integer_array then value.is_a?(Array) && value.all? { |item| item.is_a?(Integer) && item >= 0 }
          else false
          end
        end
      end

      class DefinitionValidator
        MAX_DEPTH = 4
        MAX_VALUES = 100
        TOP_LEVEL_KEYS = %w[version realm language text mode lexical_match semantic_max_distance filters].freeze

        attr_reader :errors

        def initialize(realm, definition)
          @realm = realm
          @definition = definition
          @errors = []
          validate
        end

        private

        def validate
          return errors << "must be an object" unless @definition.is_a?(Hash)

          definition = @definition.stringify_keys
          unknown = definition.keys - TOP_LEVEL_KEYS
          errors << "contains unknown keys: #{unknown.sort.join(', ')}" if unknown.any?
          errors << "version must be 1" unless definition["version"] == 1
          errors << "realm must match the saved search" unless definition["realm"] == @realm.realm_key
          mode = definition["mode"] || "filter_only"
          errors << "mode is invalid" unless MODES.include?(mode)
          if %w[lexical semantic hybrid].include?(mode) && definition["text"].blank?
            errors << "text is required for ranked modes"
          end
          if %w[semantic hybrid].include?(mode)
            threshold = definition["semantic_max_distance"]
            errors << "semantic_max_distance must be numeric" unless threshold.is_a?(Numeric)
          end
          validate_group(definition["filters"], depth: 0) if definition["filters"]
        end

        def validate_group(group, depth:)
          return errors << "filter nesting is too deep" if depth > MAX_DEPTH
          return validate_predicate(group) if group.is_a?(Hash) && group.key?("field")
          return errors << "filter group must be an object" unless group.is_a?(Hash)

          keys = group.keys.map(&:to_s)
          return errors << "filter group must contain exactly one of all, any, or not" unless keys.one? && %w[all any not].include?(keys.first)

          children = group.values.first
          children = [ children ] if keys.first == "not"
          unless children.is_a?(Array) && children.any?
            return errors << "filter group cannot be empty"
          end
          children.each do |child|
            child = child.stringify_keys if child.respond_to?(:stringify_keys)
            validate_group(child, depth: depth + 1)
          end
        end

        def validate_predicate(predicate)
          predicate = predicate.stringify_keys
          field = predicate["field"]
          op = predicate["op"]
          allowed = @realm.filter_fields[field]
          if allowed.nil?
            errors << "filter field #{field.inspect} is not allowed"
          elsif !allowed.include?(op)
            errors << "operator #{op.inspect} is not allowed for #{field}"
          end
          value = predicate["value"]
          if value.is_a?(Array) && value.length > MAX_VALUES
            errors << "filter value arrays cannot exceed #{MAX_VALUES} items"
          end
        end
      end
    end
  end
end
