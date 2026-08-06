module Warehouse::Spending::Scrapers
  class ProactiveGrants < Base
    SOURCE_URL = "https://search.open.canada.ca/grants/"

    AGREEMENT_TYPES = {
      "G" => "grant",
      "C" => "contribution",
      "O" => "transfer_payment"
    }.freeze

    private

    def each_attributes(payload)
      each_csv(payload) do |row|
        reference_number = clean(row["ref_number"])
        payer_key = clean(row["owner_org"])
        next if reference_number.blank? || payer_key.blank?

        recipient_name = clean(row["recipient_legal_name"]) ||
          clean(row["recipient_operating_name"]) ||
          clean(row["research_organization_name"])
        program_name = clean(row["prog_name_en"])
        title = clean(row["agreement_title_en"]) || program_name || recipient_name
        agreement_type = clean(row["agreement_type"]).to_s.upcase

        yield(
          external_key: stable_key(payer_key, reference_number, row["amendment_number"]),
          canonical_key: stable_key(payer_key, reference_number),
          award_type: AGREEMENT_TYPES.fetch(agreement_type, "transfer_payment"),
          language: "en",
          title: title,
          description: clean([
            row["description_en"], row["prog_purpose_en"],
            row["expected_results_en"], row["additional_information_en"]
          ]),
          payer_name: english(row["owner_org_title"]),
          recipient_name: recipient_name,
          recipient_type: clean(row["recipient_type"]),
          program_name: program_name,
          program_key: clean(row["agreement_number"]),
          fiscal_year: fiscal_year(reference_number) || fiscal_year(row["agreement_start_date"]),
          occurred_at: occurred_at(row["agreement_start_date"]),
          amount: amount(row["agreement_value"]),
          currency: "CAD",
          is_aggregated: false,
          source_url: SOURCE_URL,
          province_code: province_code(row["recipient_province"]),
          country_code: country_code(row["recipient_country"]),
          metadata: grant_metadata(row)
        )
      end
    end

    def grant_metadata(row)
      row.transform_values { |value| clean(value) }.compact.merge(
        "ref_number" => clean(row["ref_number"]),
        "amendment_number" => clean(row["amendment_number"]),
        "amendment_date" => clean(row["amendment_date"]),
        "agreement_type" => clean(row["agreement_type"]),
        "recipient_business_number" => clean(row["recipient_business_number"]),
        "recipient_operating_name" => clean(row["recipient_operating_name"]),
        "research_organization_name" => clean(row["research_organization_name"]),
        "recipient_city" => clean(row["recipient_city"]),
        "recipient_postal_code" => clean(row["recipient_postal_code"]),
        "agreement_end_date" => clean(row["agreement_end_date"]),
        "foreign_currency_type" => clean(row["foreign_currency_type"]),
        "naics_identifier" => clean(row["naics_identifier"]),
        "agreement_value" => amount(row["agreement_value"])&.to_f,
        "foreign_currency_value" => amount(row["foreign_currency_value"])&.to_f,
        "owner_org" => clean(row["owner_org"])
      ).compact
    end

    def finalize_records!
      mark_canonical_versions!(
        "CASE WHEN metadata->>'amendment_number' ~ '^\\d+$' " \
          "THEN (metadata->>'amendment_number')::integer ELSE -1 END DESC",
        "COALESCE(metadata->>'amendment_date', '') DESC",
        "COALESCE(metadata->>'ref_number', '') DESC"
      )
    end
  end
end
