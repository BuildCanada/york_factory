module Warehouse::Spending::Serializer
  module_function

  def search_document(award)
    {
      id: award.search_id,
      key: award.external_key,
      type: "canada-spends.db/#{award.source.name}",
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

  def fiscal_year_label(award)
    return "" unless award.fiscal_year

    metadata_label = award.metadata.to_h["fiscal_year_label"].to_s
    return metadata_label if metadata_label.match?(/\A\d{4}[-\/]\d{2,4}\z/)

    "#{award.fiscal_year}-#{award.fiscal_year + 1}"
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
