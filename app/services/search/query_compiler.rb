module Search
  class QueryCompiler
    OPERATORS = {
      "eq" => "Eq",
      "in" => "In",
      "gt" => "Gt",
      "gte" => "Gte",
      "lt" => "Lt",
      "lte" => "Lte",
      "contains_any" => "ContainsAny"
    }.freeze

    class InvalidDefinition < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super(errors.join(", "))
      end
    end

    attr_reader :definition, :realm

    def initialize(definition, realm: nil, evaluated_at: Time.current)
      @definition = definition.to_h.deep_stringify_keys
      @realm = Search::Realms.fetch(realm || @definition["realm"])
      @evaluated_at = evaluated_at
      errors = @realm.validate_definition(@definition)
      raise InvalidDefinition, errors if errors.any?
    end

    def filters(from_sequence: nil, to_sequence: nil, lexical_membership: false)
      predicates = [
        [ "realm", "Eq", definition.fetch("realm") ],
        [ "visibility", "Eq", "public" ]
      ]
      predicates << [ "index_sequence", "Gt", from_sequence ] unless from_sequence.nil?
      predicates << [ "index_sequence", "Lte", to_sequence ] unless to_sequence.nil?
      predicates << compile_group(definition["filters"]) if definition["filters"].present?
      predicates << lexical_filter if lexical_membership && text.present?
      predicates.compact!
      predicates.one? ? predicates.first : [ "And", predicates ]
    end

    def mode
      definition["mode"].presence || "filter_only"
    end

    def text
      definition["text"].to_s.strip.presence
    end

    def lexical_field
      definition["language"] == "fr" ? "content_fr" : "content_en"
    end

    def semantic_max_distance
      definition["semantic_max_distance"]&.to_f
    end

    private

    def compile_group(group)
      group = group.to_h.deep_stringify_keys
      return compile_predicate(group) if group.key?("field")
      return [ "And", Array(group.fetch("all")).map { |child| compile_group(child) } ] if group.key?("all")
      return [ "Or", Array(group.fetch("any")).map { |child| compile_group(child) } ] if group.key?("any")
      return [ "Not", compile_group(group.fetch("not")) ] if group.key?("not")

      raise InvalidDefinition, [ "invalid filter group" ]
    end

    def compile_predicate(predicate)
      field = predicate.fetch("field")
      operator = predicate.fetch("op")
      value = normalize_value(field, predicate["value"])

      if operator == "contains_all"
        children = Array(value).map { |item| [ field, "Contains", item ] }
        return children.one? ? children.first : [ "And", children ]
      end

      [ field, OPERATORS.fetch(operator), value ]
    end

    def normalize_value(field, value)
      return @evaluated_at.iso8601(6) if realm.field_types[field] == :datetime && value == "now"

      value
    end

    def lexical_filter
      operator = case definition["lexical_match"]
      when "phrase" then "ContainsTokenSequence"
      when "any_tokens" then "ContainsAnyToken"
      else "ContainsAllTokens"
      end
      [ lexical_field, operator, text ]
    end
  end
end
