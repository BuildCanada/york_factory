module Warehouse::Spending::Scrapers
  class AggregatedContracts < Base
    SOURCE_URL = "https://open.canada.ca/data/en/dataset/d8f85d91-7dec-4fd1-8055-483b77225d8b/resource/2e9a82e2-bb18-4bff-a61e-59af3b429672"

    AMOUNT_COLUMNS = %w[
      contracts_goods_original_value contracts_goods_amendment_value
      contracts_service_original_value contracts_service_amendment_value
      contracts_construction_original_value contracts_construction_amendment_value
      acquisition_card_transactions_total_value
    ].freeze

    private

    def each_attributes(payload)
      each_csv(payload) do |row|
        year = fiscal_year(row["year"])
        payer_key = clean(row["owner_org"])
        next if year.nil? || payer_key.blank?

        payer_name = english(row["owner_org_title"])
        components = component_amounts(row)

        yield(
          external_key: stable_key(payer_key, year),
          award_type: "contract",
          language: "en",
          title: "#{payer_name || payer_key} aggregated contracts under $10,000",
          description: description(components),
          payer_name: payer_name,
          recipient_name: "Multiple recipients",
          recipient_type: "multiple",
          program_name: "Aggregated contracts under $10,000",
          fiscal_year: year,
          occurred_at: occurred_at("#{year}-04-01"),
          amount: components.values.compact.sum,
          currency: "CAD",
          is_aggregated: true,
          source_url: SOURCE_URL,
          country_code: "CA",
          metadata: contract_metadata(row, components)
        )
      end
    end

    def component_amounts(row)
      AMOUNT_COLUMNS.index_with { |column| amount(row[column]) || 0.to_d }
    end

    def description(components)
      goods = components.values_at(
        "contracts_goods_original_value", "contracts_goods_amendment_value"
      ).sum
      services = components.values_at(
        "contracts_service_original_value", "contracts_service_amendment_value"
      ).sum
      construction = components.values_at(
        "contracts_construction_original_value", "contracts_construction_amendment_value"
      ).sum
      cards = components.fetch("acquisition_card_transactions_total_value")

      "Aggregated contracts under $10,000 — Goods: #{goods.to_s('F')}; " \
        "Services: #{services.to_s('F')}; Construction: #{construction.to_s('F')}; " \
        "Acquisition cards: #{cards.to_s('F')}"
    end

    def contract_metadata(row, components)
      {
        "owner_org" => clean(row["owner_org"]),
        "contract_goods_number_of" => row["contract_goods_number_of"].to_i,
        "contract_service_number_of" => row["contract_service_number_of"].to_i,
        "contract_construction_number_of" => row["contract_construction_number_of"].to_i,
        "acquisition_card_transactions_number_of" => row["acquisition_card_transactions_number_of"].to_i
      }.merge(components.transform_values(&:to_f))
    end
  end
end
