module Search
  module Realms
    class Kpi < Base
      RECORD_TYPES = %w[kpi].freeze
      FIELD_TYPES = {
        "kpi_measure_id" => :integer,
        "kpi_measure_name" => :string,
        "kpi_measure_slug" => :string,
        "kpi_measure_description" => :string,
        "kpi_category" => :string,
        "kpi_service_category" => :string,
        "kpi_aggregation_type" => :string,
        "kpi_frequency" => :string,
        "kpi_higher_is_bad" => :boolean,
        "kpi_unit_id" => :integer,
        "kpi_unit_symbol" => :string,
        "kpi_unit_kind" => :string,
        "kpi_currency_code" => :string,
        "kpi_last_updated_at" => :datetime
      }.freeze
      REQUIRED_FIELDS = %w[kpi_measure_id kpi_measure_name kpi_last_updated_at].freeze
      EMBEDDING_FIELDS = %w[kpi_measure_name kpi_measure_description].freeze
      FILTER_FIELDS = FIELD_TYPES.keys.index_with do |field|
        type = FIELD_TYPES.fetch(field)
        if type == :boolean
          %w[eq]
        elsif %i[integer datetime].include?(type)
          %w[eq gt gte lt lte in]
        else
          %w[eq in]
        end
      end.freeze
      FACET_FIELDS = %w[
        kpi_category kpi_service_category kpi_aggregation_type kpi_frequency
        kpi_unit_symbol
      ].freeze
      TURBOPUFFER_SCHEMA = FIELD_TYPES.to_h do |field, type|
        tp_type = case type
        when :integer then "uint"
        when :boolean then "bool"
        when :datetime then "datetime"
        else "string"
        end
        [ field.to_sym, { type: tp_type, filterable: field != "kpi_measure_description" } ]
      end.freeze
    end
  end
end
