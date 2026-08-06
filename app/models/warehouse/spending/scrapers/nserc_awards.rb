module Warehouse::Spending::Scrapers
  class NsercAwards < Base
    private

    def each_attributes(payload)
      if payload.respond_to?(:read)
        each_csv(payload) do |row|
          attributes = listing_attributes(row)
          yield attributes if attributes[:external_key].present?
        end
        return
      end

      document = payload.is_a?(Hash) ? payload : JSON.parse(payload.to_s)

      Array(document["aaData"]).each do |row|
        attributes = listing_attributes(row)
        next if attributes[:external_key].blank?

        yield attributes
      end
    end

    def listing_attributes(row)
      recipient, title, award_amount, year, program, external_key = if row.is_a?(Hash)
        [
          row["project_lead_name"] || row["recipient_name"],
          row["title"],
          row["award_amount"] || row["amount"],
          row["fiscal_year"],
          row["program"],
          row["external_id"] || row["id"]
        ]
      else
        [ row[0], row[1], row[2], row[3], row[4], row[5] ]
      end

      parsed_year = fiscal_year(year)
      external_key = clean(external_key)

      {
        external_key: external_key,
        award_type: "grant",
        title: title,
        payer_name: "Natural Sciences and Engineering Research Council of Canada",
        description: row.is_a?(Hash) ? row["description"] : nil,
        recipient_name: recipient,
        recipient_type: "individual",
        program_name: program,
        program_key: row.is_a?(Hash) ? row["program_id"] || program : program,
        fiscal_year: parsed_year,
        occurred_at: parsed_year && Time.zone.local(parsed_year, 4, 1),
        amount: amount(award_amount),
        province_code: row.is_a?(Hash) ? province_code(row["province"]) : nil,
        country_code: row.is_a?(Hash) ? country_code(row["country"]) : "CA",
        source_url: row.is_a?(Hash) ? row["source_url"] || source.url : legacy_source_url(external_key),
        metadata: {
          "fiscal_year_label" => clean(year),
          "application_id" => row.is_a?(Hash) ? clean(row["application_id"]) : external_key,
          "recipient_organization" => row.is_a?(Hash) ? clean(row["recipient_organization"]) : nil,
          "project_lead_name" => row.is_a?(Hash) ? clean(row["project_lead_name"] || recipient) : recipient,
          "competition_year" => row.is_a?(Hash) ? clean(row["competition_year"]) : parsed_year,
          "installment" => row.is_a?(Hash) ? clean(row["installment"]) : nil,
          "department" => row.is_a?(Hash) ? clean(row["department"]) : nil,
          "selection_committee" => row.is_a?(Hash) ? clean(row["selection_committee"]) : nil,
          "research_subject" => row.is_a?(Hash) ? clean(row["research_subject"]) : nil,
          "source_fields" => row.is_a?(Hash) ? source_fields(row["source_fields"]) : nil
        }.compact
      }
    end

    def source_fields(value)
      return if value.blank?

      JSON.parse(value)
    rescue JSON::ParserError
      nil
    end

    def legacy_source_url(external_key)
      return source.url if external_key.blank?

      "https://www.nserc-crsng.gc.ca/ase-oro/Details-Detailles_eng.asp?id=#{CGI.escape(external_key)}"
    end
  end
end
