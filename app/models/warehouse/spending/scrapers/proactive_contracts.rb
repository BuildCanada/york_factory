module Warehouse::Spending::Scrapers
  class ProactiveContracts < Base
    SOURCE_URL = "https://search.open.canada.ca/contracts/"
    GENERIC_PROCUREMENT_IDS = [ "null", "nil", "n a", "na", "none", "unknown" ].freeze

    POSTAL_PROVINCES = {
      "A" => "NL", "B" => "NS", "C" => "PE", "E" => "NB",
      "G" => "QC", "H" => "QC", "J" => "QC",
      "K" => "ON", "L" => "ON", "M" => "ON", "N" => "ON", "P" => "ON",
      "R" => "MB", "S" => "SK", "T" => "AB", "V" => "BC",
      "X" => "NT", "Y" => "YT"
    }.freeze

    private

    def each_attributes(payload)
      each_csv(payload) do |row|
        reference_number = clean(row["reference_number"])
        payer_key = clean(row["owner_org"])
        next if reference_number.blank? || payer_key.blank?

        payer_name = english(row["owner_org_title"]) || clean(row["buyer_name"])
        recipient_name = clean(row["vendor_name"])
        description = clean([
          row["description_en"], row["comments_en"], row["additional_comments_en"]
        ])

        yield(
          external_key: stable_key(payer_key, reference_number),
          canonical_key: contract_key(payer_key, row, reference_number),
          award_type: "contract",
          language: "en",
          title: clean(row["description_en"]) ||
            [ recipient_name, "contract" ].compact.join(" "),
          description: description,
          payer_name: payer_name,
          recipient_name: recipient_name,
          recipient_type: "vendor",
          program_name: clean(row["description_en"]),
          program_key: clean(row["economic_object_code"]),
          fiscal_year: fiscal_year(row["reporting_period"]) || fiscal_year(row["contract_date"]),
          occurred_at: occurred_at(row["contract_date"]),
          amount: amount(row["contract_value"]),
          currency: "CAD",
          is_aggregated: false,
          source_url: SOURCE_URL,
          province_code: postal_province(row["vendor_postal_code"]),
          country_code: vendor_country_code(row["country_of_vendor"]),
          metadata: contract_metadata(row)
        )
      end
    end

    def postal_province(value)
      postal_code = clean(value).to_s.upcase.gsub(/\s+/, "")
      return if postal_code.blank?
      return "NU" if postal_code.start_with?("X0A", "X0B", "X0C")

      POSTAL_PROVINCES[postal_code.first]
    end

    def vendor_country_code(value)
      country = clean(value)
      return country_code(country) if country.blank? || country.match?(/\A[A-Za-z]{2}\z/)

      {
        "Canada" => "CA",
        "United States" => "US",
        "United States of America" => "US",
        "Viet Nam" => "VN",
        "Vietnam" => "VN"
      }[country]
    end

    def contract_metadata(row)
      row.transform_values { |value| clean(value) }.compact.merge(
        "reference_number" => clean(row["reference_number"]),
        "procurement_id" => clean(row["procurement_id"]),
        "buyer_name" => clean(row["buyer_name"]),
        "vendor_postal_code" => clean(row["vendor_postal_code"]),
        "contract_period_start" => clean(row["contract_period_start"]),
        "delivery_date" => clean(row["delivery_date"]),
        "commodity_type" => clean(row["commodity_type"]),
        "commodity_code" => clean(row["commodity_code"]),
        "country_of_vendor" => clean(row["country_of_vendor"]),
        "indigenous_business" => clean(row["indigenous_business"]),
        "reporting_period" => clean(row["reporting_period"]),
        "contract_value" => amount(row["contract_value"])&.to_f,
        "original_value" => amount(row["original_value"])&.to_f,
        "amendment_value" => amount(row["amendment_value"])&.to_f,
        "owner_org" => clean(row["owner_org"])
      ).compact
    end

    def contract_key(payer_key, row, reference_number)
      procurement_id = clean(row["procurement_id"])
      identity = generic_procurement_id?(procurement_id) ? reference_number : procurement_id
      stable_key(payer_key, identity)
    end

    def generic_procurement_id?(procurement_id)
      normalized = procurement_id.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
      procurement_id.blank? || GENERIC_PROCUREMENT_IDS.include?(normalized) ||
        normalized.include?("acquisition card")
    end

    # The disclosure feed keeps the original contract and every amendment as
    # separate rows. They share the reporting organization's procurement ID,
    # while each disclosure has its own reference number. Retain every version
    # in the warehouse, but identify only the latest disclosure as canonical so
    # cumulative contract values are not counted more than once in search.
    def finalize_records!
      mark_canonical_versions!(
        "COALESCE(metadata->>'reporting_period', '') DESC",
        "COALESCE(metadata->>'reference_number', '') DESC"
      )
    end
  end
end
