module Warehouse::Spending
  class Search
    InvalidRequest = Class.new(ArgumentError)
    Result = Data.define(:records, :found, :page, :per_page, :facets, :query, :elapsed_ms)

    FACETS = {
      "payer" => :payer_name,
      "fiscal_year" => :fiscal_year,
      "recipient" => :recipient_name,
      "province" => :province_code,
      "country" => :country_code,
      "program" => :program_name,
      "award_type" => :award_type,
      "is_aggregated" => :is_aggregated
    }.freeze
    MAX_PER_PAGE = 250
    MAX_PAGE = 10_000
    MAX_QUERY_LENGTH = 500
    DEFAULT_FACETS = FACETS.keys.first(7).freeze

    def initialize(parameters)
      @parameters = parameters.to_h.stringify_keys
    end

    def call
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      scope = apply_query(apply_filters(base_scope))
      found = scope.count
      records = ordered(scope).offset((page - 1) * per_page).limit(per_page).to_a
      facets = requested_facets.index_with { |name| facet_counts(scope, name) }
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round

      Result.new(records:, found:, page:, per_page:, facets:, query:, elapsed_ms:)
    end

    private

    attr_reader :parameters

    def base_scope
      Warehouse::SpendingAward.search_indexable.includes(:source)
    end

    def query
      value = parameters["q"].to_s.strip
      value = "" if value == "*"
      raise InvalidRequest, "q is too long" if value.length > MAX_QUERY_LENGTH

      value
    end

    def apply_query(scope)
      return scope if query.blank?

      scope.where(
        "to_tsvector('simple', " \
          "coalesce(warehouse.spending_awards.recipient_name, '') || ' ' || " \
          "coalesce(warehouse.spending_awards.program_name, '') || ' ' || " \
          "coalesce(warehouse.spending_awards.description, '') || ' ' || " \
          "coalesce(warehouse.spending_awards.title, '')) @@ websearch_to_tsquery('simple', ?)",
        query
      )
    end

    def apply_filters(scope)
      FilterParser.new(parameters["filter_by"]).filters.reduce(scope) do |relation, filter|
        apply_filter(relation, filter)
      end
    end

    def apply_filter(scope, filter)
      field = FACETS.fetch(filter.fetch(:field))
      values = filter.fetch(:values)

      if filter[:range]
        scope.where(field => filter.fetch(:range))
      elsif filter[:operator] == :not
        scope.where.not(field => cast_values(field, values))
      else
        scope.where(field => cast_values(field, values))
      end
    end

    def cast_values(field, values)
      values.map do |value|
        case field
        when :fiscal_year then value.to_s[/\d{4}/].to_i
        when :is_aggregated then ActiveModel::Type::Boolean.new.cast(value)
        when :province_code then Warehouse::Spending::Geography.province_code(value)
        when :country_code then Warehouse::Spending::Geography.country_code(value)
        else value
        end
      end
    end

    def ordered(scope)
      case parameters["sort_by"].to_s
      when "", "_text_match:desc"
        query.present? ? scope.order(Arel.sql("ts_rank_cd(to_tsvector('simple', coalesce(recipient_name, '') || ' ' || coalesce(program_name, '') || ' ' || coalesce(description, '') || ' ' || coalesce(title, '')), websearch_to_tsquery('simple', #{Warehouse::SpendingAward.connection.quote(query)})) DESC"), id: :asc) : scope.order(id: :asc)
      when "amount:desc"
        scope.order(Arel.sql("amount DESC NULLS LAST"), id: :asc)
      when "amount:asc"
        scope.order(Arel.sql("amount ASC NULLS LAST"), id: :asc)
      else
        raise InvalidRequest, "unsupported sort_by #{parameters['sort_by'].inspect}"
      end
    end

    def facet_counts(scope, name)
      field = FACETS.fetch(name)
      query = scope.unscope(:includes, :order, :limit, :offset).where.not(field => nil)
      query = apply_facet_query(query, name, field)
      counts = query.group(field).order(Arel.sql("count_all DESC"), field => :asc).limit(max_facet_values).count

      counts.map do |value, count|
        display = display_facet_value(field, value)
        { value: display, count:, highlighted: highlight(display) }
      end
    end

    def apply_facet_query(scope, name, field)
      facet_name, text = parameters["facet_query"].to_s.split(":", 2)
      return scope unless facet_name == name && text.present?
      return scope.where(field => text.to_s[/\d{4}/].to_i) if field == :fiscal_year
      if field == :province_code
        return scope.where(field => Warehouse::Spending::Geography.matching_province_codes(text))
      end
      if field == :country_code
        return scope.where(field => Warehouse::Spending::Geography.matching_country_codes(text))
      end

      scope.where("#{Warehouse::SpendingAward.connection.quote_column_name(field)} ILIKE ?", "%#{Warehouse::SpendingAward.sanitize_sql_like(text)}%")
    end

    def display_facet_value(field, value)
      case field
      when :fiscal_year then "#{value}-#{value + 1}"
      when :province_code then Warehouse::Spending::Geography.province_name(value)
      when :country_code then Warehouse::Spending::Geography.country_name(value)
      else value.to_s
      end
    end

    def highlight(value)
      _name, text = parameters["facet_query"].to_s.split(":", 2)
      return value if text.blank?

      value.gsub(/#{Regexp.escape(text)}/i) { |match| "<mark>#{match}</mark>" }
    end

    def requested_facets
      values = parameters["facet_by"].to_s.split(",").map { |value| value.split("(", 2).first }.compact_blank
      values = DEFAULT_FACETS if values.empty? || values.include?("*")
      unknown = values - FACETS.keys
      raise InvalidRequest, "unsupported facets: #{unknown.join(', ')}" if unknown.any?

      values.uniq
    end

    def page
      @page ||= Integer(parameters["page"].presence || 1).clamp(1, MAX_PAGE)
    rescue ArgumentError, TypeError
      raise InvalidRequest, "page must be an integer"
    end

    def per_page
      @per_page ||= Integer(parameters["per_page"].presence || 25).clamp(0, MAX_PER_PAGE)
    rescue ArgumentError, TypeError
      raise InvalidRequest, "per_page must be an integer"
    end

    def max_facet_values
      @max_facet_values ||= Integer(parameters["max_facet_values"].presence || 30).clamp(1, 100)
    rescue ArgumentError, TypeError
      raise InvalidRequest, "max_facet_values must be an integer"
    end

    class FilterParser
      MAX_FILTERS = 20
      MAX_VALUES = 100

      def initialize(value)
        @value = value.to_s.strip
      end

      def filters
        return [] if @value.blank?

        clauses = split_clauses
        raise InvalidRequest, "too many filters" if clauses.length > MAX_FILTERS

        clauses.map { |clause| parse(clause) }
      end

      private

      def split_clauses
        @value.split(/\s+&&\s+/)
      end

      def parse(clause)
        match = clause.match(/\A([a-z_]+):(!=|=|!|>=|<=|>|<)?\s*(.+)\z/)
        raise InvalidRequest, "invalid filter #{clause.inspect}" unless match

        field, raw_operator, raw_value = match.captures
        raise InvalidRequest, "unsupported filter #{field.inspect}" unless FACETS.key?(field)

        operator = %w[!= !].include?(raw_operator) ? :not : :equal
        if (range = parse_range(raw_value))
          raise InvalidRequest, "ranges are only supported for fiscal_year" unless field == "fiscal_year"

          return { field:, operator:, values: [], range: }
        end

        values = unwrap_array(raw_value).map { |value| unquote(value) }
        raise InvalidRequest, "filter values cannot be empty" if values.empty?
        raise InvalidRequest, "too many filter values" if values.length > MAX_VALUES

        { field:, operator:, values: }
      end

      def parse_range(value)
        match = value.match(/\A=?\[\s*(\d{4})\s*\.\.\s*(\d{4})\s*\]\z/)
        match && (match[1].to_i..match[2].to_i)
      end

      def unwrap_array(value)
        text = value.sub(/\A=/, "").strip
        text = text[1...-1] if text.start_with?("[") && text.end_with?("]")
        text.scan(/`(?:[^`]|``)*`|[^,]+/).map(&:strip).reject(&:blank?)
      end

      def unquote(value)
        value = value[1...-1].gsub("``", "`") if value.start_with?("`") && value.end_with?("`")
        value
      end
    end
  end
end
