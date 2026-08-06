module Warehouse::Spending::Scrapers
  class SshrcAwards < Base
    private

    def each_attributes(payload)
      if payload.respond_to?(:read) || canonical_csv?(payload)
        each_csv(payload) do |record|
          attributes = normalized_attributes(record)
          yield attributes if attributes[:external_key].present?
        end
        return
      end

      records = json_records(payload)
      if records
        records.each { |record| yield normalized_attributes(record) }
      else
        yield html_attributes(payload)
      end
    end

    def json_records(payload)
      document = if payload.is_a?(Array) || payload.is_a?(Hash)
        payload
      elsif payload.to_s.lstrip.start_with?("[", "{")
        JSON.parse(payload.to_s)
      end

      case document
      when Array then document
      when Hash then document["records"] || document[:records]
      end
    end

    def normalized_attributes(record)
      record = record.to_h.stringify_keys
      applicant = record["applicant"] || record["project_lead_name"] || record["recipient_name"]
      organization = record["organization"] || record["institution"] || record["recipient_organization"]
      recipient_role = record["recipient_role"] || record["role"]
      year = record["fiscal_year"]
      external_key = clean(record["external_key"] || record["external_id"] || record["id"])
      external_key ||= stable_key(record["title"], applicant, organization, year, record["amount"])
      province = province_code(record["province"] || province_from(organization))
      institutional_recipient = recipient_role.to_s.match?(/institution|general support/i)

      {
        external_key: external_key,
        award_type: "grant",
        title: record["title"],
        description: record["abstract"] || record["description"],
        payer_name: "Social Sciences and Humanities Research Council of Canada",
        recipient_name: applicant.presence || organization,
        recipient_type: applicant.present? && !institutional_recipient ? "individual" : "organization",
        program_name: record["program"],
        program_key: record["program"],
        fiscal_year: fiscal_year(year),
        occurred_at: record["occurred_at"].present? ? occurred_at(record["occurred_at"]) : fiscal_year_start(year),
        amount: amount(record["amount"] || record["award_amount"]),
        province_code: province,
        country_code: country_code(record["country"]) || (province && "CA"),
        source_url: record["source_url"].presence || detail_url(external_key),
        metadata: {
          "competition_year" => clean(record["competition_year"]),
          "application_id" => clean(record["application_id"]),
          "recipient_role" => clean(recipient_role),
          "applicant" => clean(applicant),
          "organization" => clean(organization),
          "discipline" => clean(record["discipline"]),
          "main_discipline" => clean(record["main_discipline"]),
          "area_of_research" => clean(record["area_of_research"]),
          "co_applicant" => clean(record["co_applicant"]),
          "keywords" => clean(record["keywords"]),
          "fiscal_year_label" => clean(year),
          "source_fields" => source_fields(record["source_fields"])
        }.compact
      }
    end

    def canonical_csv?(payload)
      payload.to_s.lines.first.to_s.delete_prefix("\uFEFF").split(",").include?("external_id")
    end

    def source_fields(value)
      return if value.blank?

      JSON.parse(value)
    rescue JSON::ParserError
      nil
    end

    def html_attributes(payload)
      document = Nokogiri::HTML(payload.to_s)
      values = %w[
        Cle Id Titre Programme Fiscal Competition Chercheur Organisation Montant
        Discipline Sujet CoChercheur Keywords Abstract
      ].index_with { |name| info(document, name) }
      external_key = values["Cle"].presence || values["Id"].presence || id_from_links(document)
      external_key ||= stable_key(values.values_at("Titre", "Chercheur", "Organisation", "Fiscal", "Montant"))
      province = province_code(province_from(values["Organisation"]))

      {
        external_key: external_key,
        award_type: "grant",
        title: values["Titre"],
        description: values["Abstract"],
        payer_name: "Social Sciences and Humanities Research Council of Canada",
        recipient_name: values["Chercheur"].presence || values["Organisation"],
        recipient_type: values["Chercheur"].present? ? "individual" : "organization",
        program_name: values["Programme"],
        program_key: values["Programme"],
        fiscal_year: fiscal_year(values["Fiscal"]),
        occurred_at: fiscal_year_start(values["Fiscal"]),
        amount: amount(values["Montant"]),
        province_code: province,
        country_code: province && "CA",
        source_url: detail_url(external_key),
        metadata: {
          "competition_year" => values["Competition"],
          "applicant" => values["Chercheur"],
          "organization" => values["Organisation"],
          "discipline" => values["Discipline"],
          "area_of_research" => values["Sujet"],
          "co_applicant" => values["CoChercheur"],
          "keywords" => values["Keywords"],
          "fiscal_year_label" => values["Fiscal"]
        }
      }
    end

    def info(document, name)
      clean(document.at_css("#Info#{name}")&.text)
    end

    def id_from_links(document)
      document.css("a[href]").filter_map do |link|
        link["href"]&.match(/[?&]Cle=([^&]+)/i)&.captures&.first
      end.first.then { |value| value && CGI.unescape(value) }
    end

    def detail_url(external_key)
      return source.url if external_key.blank?

      "http://www.outil.ost.uqam.ca/CRSH/Detail.aspx?Cle=#{CGI.escape(external_key)}&Langue=2"
    end

    def province_from(organization)
      text = clean(organization)
      return if text.blank?

      PROVINCE_CODES.keys.find { |name| text.downcase.match?(/(?:,|\b)\s*#{Regexp.escape(name)}\s*\z/) }
    end

    def fiscal_year_start(value)
      year = fiscal_year(value)
      year && Time.zone.local(year, 4, 1)
    end
  end
end
