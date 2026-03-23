module CorporateNormalization
  extend ActiveSupport::Concern

  BATCH_SIZE = 5_000

  STATUS_MAP = {
    "Active" => "Active",
    "ACTIF" => "Active",
    "Dissolved" => "Dissolved",
    "DISSOUS" => "Dissolved",
    "Amalgamated" => "Amalgamated",
    "FUSIONNÉ" => "Amalgamated",
    "Revoked" => "Revoked",
    "RÉVOQUÉ" => "Revoked",
    "Cancelled" => "Cancelled",
    "ANNULÉ" => "Cancelled",
    "Continued Out" => "Continued Out",
    "Inactive" => "Inactive"
  }.freeze

  private

  def normalize_status(raw_status)
    return nil if raw_status.blank?
    STATUS_MAP[raw_status.strip] || raw_status.strip.titleize
  end

  def normalize_name(name)
    return nil if name.blank?
    name.strip
      .gsub(/\s+/, " ")
      .gsub("\u2019", "'")
      .gsub("\u2018", "'")
      .gsub("\u201C", '"')
      .gsub("\u201D", '"')
  end

  def normalize_province(province_raw)
    return nil if province_raw.blank?

    PROVINCE_MAP[province_raw.strip.upcase] || province_raw.strip.upcase[0, 2]
  end

  PROVINCE_MAP = {
    "ONTARIO" => "ON", "ON" => "ON",
    "QUEBEC" => "QC", "QUÉBEC" => "QC", "QC" => "QC",
    "BRITISH COLUMBIA" => "BC", "BC" => "BC",
    "ALBERTA" => "AB", "AB" => "AB",
    "MANITOBA" => "MB", "MB" => "MB",
    "SASKATCHEWAN" => "SK", "SK" => "SK",
    "NOVA SCOTIA" => "NS", "NS" => "NS",
    "NEW BRUNSWICK" => "NB", "NB" => "NB",
    "NEWFOUNDLAND AND LABRADOR" => "NL", "NL" => "NL",
    "PRINCE EDWARD ISLAND" => "PE", "PE" => "PE",
    "NORTHWEST TERRITORIES" => "NT", "NT" => "NT",
    "YUKON" => "YT", "YT" => "YT",
    "NUNAVUT" => "NU", "NU" => "NU"
  }.freeze

  def batch_upsert!(records)
    return if records.empty?

    CorporateEntity.upsert_all(
      records,
      unique_by: [:jurisdiction, :registry_id],
      update_only: [:legal_name, :corporation_type, :status, :governing_act,
                     :registered_office_address, :registered_office_province,
                     :registered_office_postal_code, :incorporation_date,
                     :dissolution_date, :business_activity, :source_system,
                     :raw_data, :raw_ingestion_id]
    )
  end
end
