module Warehouse::Spending::Scrapers
  class GlobalAffairsProjects < Base
    STATUS_NAMES = {
      "1" => "pipeline",
      "2" => "implementation",
      "3" => "finalisation",
      "4" => "closed",
      "5" => "cancelled",
      "6" => "suspended"
    }.freeze

    private

    def each_attributes(payload)
      if xml_payload?(payload)
        each_legacy_attributes(payload) { |attributes| yield attributes }
        return
      end

      each_csv(payload) do |row|
        organizations = json_array(row["implementing_organizations"])
        countries = json_array(row["countries"])
        regions = json_array(row["regions"])
        sectors = json_array(row["sectors"])
        policy_markers = json_array(row["policy_markers"])
        results = json_array(row["results"])
        source_fields = json_object(row["source_fields"])
        status_code = row["status"]

        yield({
          external_key: row["external_id"],
          award_type: "contribution",
          title: row["title"],
          description: row["description"],
          payer_name: "Global Affairs Canada",
          recipient_name: organizations.pluck("name"),
          recipient_type: "organization",
          program_key: row["external_id"],
          fiscal_year: fiscal_year(row["start_date"]),
          occurred_at: occurred_at(row["start_date"]),
          amount: amount(row["commitment_amount"]),
          currency: row["currency"],
          country_code: country_code(countries.first&.fetch("code", nil)),
          source_url: row["detail_url"].presence || row["source_url"].presence || source.url,
          metadata: {
            "status" => STATUS_NAMES[status_code] || status_code,
            "status_code" => status_code,
            "end_date" => row["end_date"],
            "implementing_organizations" => organizations,
            "countries" => display_elements(countries),
            "regions" => display_elements(regions),
            "sectors" => display_elements(sectors),
            "policy_markers" => display_elements(policy_markers, qualifier: "significance"),
            "iati_countries" => countries,
            "iati_regions" => regions,
            "iati_sectors" => sectors,
            "iati_policy_markers" => policy_markers,
            "aid_type" => row["aid_type"],
            "collaboration_type" => row["collaboration_type"],
            "finance_type" => row["finance_type"],
            "results" => results,
            "expected_results" => result_description(results, "expected"),
            "results_achieved" => result_description(results, "achieved"),
            "reporting_organisation" => source_fields.dig("reporting_organization", "name"),
            "iati_source_url" => row["source_url"],
            "iati_source_fields" => source_fields,
            "date_modified" => source_fields["last_updated_datetime"]
          }
        })
      end
    end

    def each_legacy_attributes(payload)
      document = Nokogiri::XML(payload_text(payload)) { |config| config.strict.nonet }

      document.xpath("/projects/project").each do |project|
        project_number = text(project, "projectNumber")
        next if project_number.blank?

        partner = text(project, "executingAgencyPartner").presence ||
          text(project, "participatingOrgs/participatingOrg")
        country = project.at_xpath("participatingOrgs/participatingOrg")&.[]("countryCode")
        start_date = text(project, "start")

        yield({
          external_key: project_number,
          award_type: "contribution",
          title: text(project, "title"),
          description: text(project, "description"),
          payer_name: "Global Affairs Canada",
          recipient_name: partner,
          recipient_type: "organization",
          program_name: text(project, "programName"),
          program_key: project_number,
          fiscal_year: fiscal_year(start_date),
          occurred_at: occurred_at(start_date),
          amount: amount(text(project, "maximumContribution")),
          country_code: country_code(country),
          source_url: source.url,
          metadata: {
            "status" => text(project, "status"),
            "date_modified" => text(project, "dateModified"),
            "end_date" => text(project, "end"),
            "contributing_organization" => text(project, "ContributingOrganization"),
            "expected_results" => text(project, "expectedResults"),
            "results_achieved" => text(project, "resultsAchieved"),
            "aid_type" => text(project, "aidType"),
            "collaboration_type" => text(project, "collaborationType"),
            "finance_type" => text(project, "financeType"),
            "reporting_organisation" => text(project, "reportingOrganisation"),
            "selection_mechanism" => text(project, "selectionMechanism"),
            "countries" => project.xpath("countries/country").map { |node| clean(node.text) },
            "sectors" => project.xpath("DACSectors/DACSectors").map { |node| clean(node.text) },
            "policy_markers" => project.xpath("policyMarkers/policyMarker").map { |node| clean(node.text) },
            "regions" => project.xpath("regions/region").map { |node| clean(node.text) }
          }
        })
      end
    end

    def xml_payload?(payload)
      sample = if payload.respond_to?(:read)
        payload.rewind
        payload.read(1_024).tap { payload.rewind }
      else
        payload.to_s.first(1_024)
      end
      sample = sample.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      sample.delete_prefix("\uFEFF").lstrip.start_with?("<")
    end

    def payload_text(payload)
      return payload.to_s unless payload.respond_to?(:read)

      begin
        payload.rewind
        payload.read
      ensure
        payload.rewind
      end
    end

    def json_array(value)
      return [] if value.blank?

      JSON.parse(value).then { |parsed| parsed.is_a?(Array) ? parsed : raise(JSON::ParserError, "expected a JSON array") }
    end

    def json_object(value)
      return {} if value.blank?

      JSON.parse(value).then { |parsed| parsed.is_a?(Hash) ? parsed : raise(JSON::ParserError, "expected a JSON object") }
    end

    def display_elements(elements, qualifier: nil)
      elements.filter_map do |element|
        label = element["name"].presence || element["code"].presence
        next if label.blank?

        label = "#{label} #{element['percentage']}%" if element["percentage"].present?
        label = "#{label} (#{qualifier}: #{element[qualifier]})" if qualifier && element[qualifier].present?
        label
      end
    end

    def result_description(results, kind)
      selected = results.select { |result| result["title"].to_s.downcase.include?(kind) }
      descriptions = selected.flat_map do |result|
        [ result["description"], *Array(result["indicators"]).pluck("description") ]
      end
      descriptions.compact_blank.uniq.join("\n\n").presence
    end

    def text(node, path)
      clean(node.at_xpath(path)&.text)
    end
  end
end
