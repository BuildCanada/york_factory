module Warehouse::Spending::Scrapers
  class CihrAwards < Base
    private

    def each_attributes(payload)
      each_record(payload) do |record|
        external_key = clean(record["id"])
        next if external_key.blank?

        competition_value = clean(record["competitiondate"])
        competition_timestamp = competition_date(competition_value)

        yield({
          external_key: external_key,
          award_type: "grant",
          title: clean(record["projecttitle"]),
          description: clean(record["abstract"]),
          payer_name: "Canadian Institutes of Health Research",
          recipient_name: clean(record["orgname"] || record["orgnameinp2"]),
          recipient_type: "organization",
          program_name: clean(record["programname2"]),
          program_key: clean(record["programname2"]),
          fiscal_year: competition_fiscal_year(competition_timestamp, competition_value),
          occurred_at: competition_timestamp,
          amount: amount(record["cihramount2"]),
          province_code: province_code(record["region"]),
          country_code: country_code(record["country"]),
          source_url: "https://webapps.cihr-irsc.gc.ca/decisions/p/project_details.html?applId=#{CGI.escape(external_key)}&lang=en",
          metadata: {
            "project_lead_name" => clean(record["name"]),
            "province" => clean(record["region"]),
            "country" => clean(record["country"]),
            "co_researchers" => clean(record["pinamesdelim"]),
            "competition_date" => competition_value,
            "program_type" => clean(record["programtype2"]),
            "theme" => clean(record["theme2"]),
            "research_subject" => clean(record["instname2"]),
            "keywords" => clean(record["keyworddelim"]),
            "duration" => clean(record["approvedterm2"]),
            "contribution" => clean(record["cihrcontribution2"]),
            "equipment_amount" => clean(record["cihrequipment2"])
          }
        })
      end
    end

    def each_record(payload, &block)
      if payload.is_a?(Hash)
        Array(payload.dig("response", "docs")).each(&block)
      elsif payload.respond_to?(:read)
        each_ndjson_record(payload, &block)
      else
        each_string_record(payload.to_s, &block)
      end
    end

    def each_string_record(payload, &block)
      document = JSON.parse(payload)
      if document.is_a?(Hash) && document.key?("response")
        Array(document.dig("response", "docs")).each(&block)
      else
        yield document
      end
    rescue JSON::ParserError
      each_ndjson_record(StringIO.new(payload), &block)
    end

    def each_ndjson_record(payload)
      payload.each_line.with_index(1) do |line, line_number|
        next if line.blank?

        yield JSON.parse(line)
      rescue JSON::ParserError => error
        raise "Invalid CIHR NDJSON on line #{line_number}: #{error.message}"
      end
    end

    def competition_date(value)
      return if value.blank?

      if (match = value.match(/\A(\d{4})(\d{2})(?:\d{2})?\z/))
        Time.zone.local(match[1].to_i, match[2].to_i, 1)
      else
        occurred_at(value)
      end
    rescue ArgumentError
      nil
    end

    def competition_fiscal_year(timestamp, value)
      return fiscal_year(value) unless timestamp

      timestamp.year - (timestamp.month < 4 ? 1 : 0)
    end
  end
end
