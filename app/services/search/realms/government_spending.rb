module Search
  module Realms
    class GovernmentSpending < Base
      RECORD_TYPES = %w[
        contract grant contribution transfer_payment fiscal_expenditure
        standard_object_expenditure
      ].freeze
      FIELD_TYPES = {
        "external_key" => :string,
        "award_type" => :string,
        "payer_organization_ids" => :integer_array,
        "payer_names" => :string_array,
        "recipient_name" => :string,
        "recipient_entity_id" => :string,
        "program_name" => :string,
        "program_key" => :string,
        "fiscal_year" => :integer,
        "occurred_at" => :datetime,
        "amount" => :number,
        "currency" => :string,
        "is_aggregated" => :boolean,
        "dataset_key" => :string
      }.freeze
      REQUIRED_FIELDS = %w[award_type dataset_key].freeze
      EMBEDDING_FIELDS = %w[recipient_name program_name award_type].freeze
      FILTER_FIELDS = {
        "award_type" => %w[eq in],
        "payer_organization_ids" => %w[contains_any contains_all],
        "recipient_name" => %w[eq in],
        "program_name" => %w[eq in],
        "program_key" => %w[eq in],
        "fiscal_year" => %w[eq gt gte lt lte in],
        "occurred_at" => %w[eq gt gte lt lte],
        "amount" => %w[eq gt gte lt lte],
        "currency" => %w[eq in],
        "is_aggregated" => %w[eq],
        "dataset_key" => %w[eq in]
      }.freeze
      FACET_FIELDS = %w[
        award_type payer_organization_ids recipient_name program_name fiscal_year
        currency dataset_key
      ].freeze
      TURBOPUFFER_SCHEMA = {
        external_key: { type: "string", filterable: false },
        award_type: { type: "string", filterable: true },
        payer_organization_ids: { type: "[]uint", filterable: true },
        payer_names: { type: "[]string", filterable: false },
        recipient_name: { type: "string", filterable: true },
        recipient_entity_id: { type: "uuid", filterable: true },
        program_name: { type: "string", filterable: true, full_text_search: true },
        program_key: { type: "string", filterable: true },
        fiscal_year: { type: "uint", filterable: true },
        occurred_at: { type: "datetime", filterable: true },
        amount: { type: "float", filterable: true },
        currency: { type: "string", filterable: true },
        is_aggregated: { type: "bool", filterable: true },
        dataset_key: { type: "string", filterable: true }
      }.freeze
    end
  end
end
