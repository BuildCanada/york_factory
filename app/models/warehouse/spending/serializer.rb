module Warehouse::Spending::Serializer
  module_function

  def search_document(award)
    slug = Warehouse::Spending::Datasets.slug_for(award.source.name)

    {
      id: award.search_id,
      key: award.external_key,
      type: "canada-spends.db/#{slug}",
      recipient: award.recipient_name.to_s,
      vendor_name: award.award_type == "contract" ? award.recipient_name.to_s : nil,
      payer: award.payer_name.to_s,
      fiscal_year: fiscal_year_label(award),
      program: award.program_name.to_s,
      timestamp: award.occurred_at&.iso8601.to_s,
      amount: award.amount&.to_f || 0.0,
      description: award.description.presence || award.title,
      award_type: award.award_type,
      province: geography_value(award, :province),
      country: geography_value(award, :country),
      is_aggregated: award.is_aggregated? ? 1 : 0,
      source_url: award.source_url
    }.compact
  end

  def normalized(award)
    search_document(award).merge(
      objectID: award.search_id,
      state: award.state,
      language: award.language,
      title: award.title,
      recipient_type: award.recipient_type,
      program_key: award.program_key,
      currency: award.currency,
      source: {
        name: award.source.name,
        url: award.source.url,
        attribution: award.source.attribution,
        license: award.source.license
      },
      metadata: award.metadata,
      first_seen_at: award.first_seen_at&.iso8601,
      last_seen_at: award.last_seen_at&.iso8601
    )
  end

  def legacy(award, slug:)
    metadata = award.metadata.to_h

    case slug
    when "contracts-over-10k"
      metadata.merge(
        "rowid" => metadata["rowid"] || award.external_key,
        "vendor_name" => award.recipient_name,
        "description_en" => metadata["description_en"] || award.title,
        "contract_value" => award.amount&.to_f,
        "source_url" => award.source_url
      ).compact
    when "nserc_grants"
      {
        "fiscal_year" => fiscal_year_label(award),
        "title" => award.title,
        "source_url" => award.source_url,
        "institution" => metadata["recipient_organization"] || award.recipient_name,
        "award_amount" => award.amount&.to_f,
        "program" => award.program_name,
        "award_summary" => award.description,
        "competition_year" => metadata["competition_year"] || award.fiscal_year,
        "installment" => metadata["installment"],
        "project_lead_name" => metadata["project_lead_name"] || award.recipient_name,
        "department" => metadata["department"],
        "province" => geography_value(award, :province),
        "selection_committee" => metadata["selection_committee"],
        "research_subject" => metadata["research_subject"],
        "application_id" => metadata["application_id"] || award.external_key
      }
    when "cihr_grants"
      {
        "competition_year" => metadata["competition_date"].presence ||
          award.occurred_at&.iso8601 || award.fiscal_year.to_s,
        "title" => award.title,
        "source_url" => award.source_url,
        "institution" => award.recipient_name,
        "award_amount" => award.amount&.to_f,
        "program" => award.program_name,
        "abstract" => award.description.to_s,
        "keywords" => metadata["keywords"].to_s,
        "project_lead_name" => metadata["project_lead_name"],
        "province" => geography_value(award, :province),
        "duration" => metadata["duration"],
        "program_type" => metadata["program_type"],
        "theme" => metadata["theme"],
        "research_subject" => metadata["research_subject"],
        "external_id" => award.external_key
      }
    when "sshrc_grants"
      {
        "fiscal_year" => fiscal_year_label(award),
        "title" => award.title,
        "source_url" => award.source_url,
        "applicant" => metadata["applicant"] || award.recipient_name,
        "amount" => award.amount&.to_f,
        "program" => award.program_name,
        "keywords" => metadata["keywords"].to_s,
        "organization" => metadata["organization"],
        "co_applicant" => metadata["co_applicant"],
        "competition_year" => metadata["competition_year"],
        "discipline" => metadata["discipline"],
        "area_of_research" => metadata["area_of_research"]
      }
    when "global_affairs_grants"
      {
        "start" => award.occurred_at&.iso8601,
        "title" => award.title,
        "source_url" => award.source_url,
        "executingAgencyPartner" => award.recipient_name,
        "maximumContribution" => award.amount&.to_f,
        "programName" => award.program_name,
        "description" => award.description,
        "projectNumber" => award.external_key,
        "status" => metadata["status"],
        "end" => metadata["end_date"],
        "countries" => array_display(metadata["countries"]),
        "ContributingOrganization" => metadata["contributing_organization"],
        "expectedResults" => metadata["expected_results"],
        "resultsAchieved" => metadata["results_achieved"],
        "aidType" => metadata["aid_type"],
        "collaborationType" => metadata["collaboration_type"],
        "financeType" => metadata["finance_type"],
        "reportingOrganisation" => metadata["reporting_organisation"],
        "selectionMechanism" => metadata["selection_mechanism"],
        "regions" => Array(metadata["regions"]).to_json,
        "DACSectors" => Array(metadata["sectors"]).to_json,
        "policyMarkers" => Array(metadata["policy_markers"]).to_json
      }
    when "transfers"
      metadata.merge(
        "FSCL_YR" => metadata["FSCL_YR"] || fiscal_year_label(award),
        "MINE" => metadata["MINE"] || metadata["ministry_name"],
        "MINC" => metadata["MINC"] || metadata["ministry_code"],
        "RCPNT_NML_EN_DESC" => metadata["RCPNT_NML_EN_DESC"] || award.recipient_name,
        "AGRG_PYMT_AMT" => award.amount&.to_f,
        "PROVTER_EN" => metadata["PROVTER_EN"] || award.province_code,
        "CNTRY_EN_NM" => metadata["CNTRY_EN_NM"] || award.country_code,
        "RCPNT_CLS_EN_DESC" => metadata["RCPNT_CLS_EN_DESC"] || award.program_name,
        "DEPT_EN_DESC" => metadata["DEPT_EN_DESC"] || award.payer_name
      ).compact
    else
      normalized(award)
    end
  end

  def fiscal_year_label(award)
    return "" unless award.fiscal_year

    metadata_label = award.metadata.to_h["fiscal_year_label"].to_s
    return metadata_label if metadata_label.match?(/\A\d{4}[-\/]\d{2,4}\z/)

    "#{award.fiscal_year}-#{award.fiscal_year + 1}"
  end

  def array_display(value)
    Array(value).compact_blank.join(", ")
  end

  def geography_value(award, kind)
    metadata = award.metadata.to_h
    if kind == :province
      metadata["PROVTER_EN"].presence ||
        metadata.dig("source_fields", "ProvinceEN").presence ||
        Warehouse::Spending::Geography.province_name(award.province_code)
    else
      metadata["CNTRY_EN_NM"].presence ||
        metadata.dig("source_fields", "CountryEN").presence ||
        Warehouse::Spending::Geography.country_name(award.country_code)
    end
  end
end
