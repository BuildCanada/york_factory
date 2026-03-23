class RawIngestion::OdbizNormalizer < ActiveRecord::AssociatedObject
  performs :normalize

  BATCH_SIZE = 5_000

  # Real ODBiz CSV columns (Statistics Canada Open Database of Businesses):
  # idx, business_name, alt_business_name, business_sector, business_subsector,
  # business_description, business_id_no, licence_number, licence_type,
  # derived_NAICS, source_NAICS_primary, source_NAICS_secondary, NAICS_descr,
  # NAICS_descr2, latitude, longitude, full_address, postal_code, unit,
  # street_no, street_name, street_direction, street_type, city, prov_terr,
  # total_no_employees, status, provider, geo_source, CSDUID, CSDNAME, PRUID

  def normalize(file_content:)
    records = []
    rows_processed = 0

    csv_content = extract_csv(file_content)

    CSV.parse(csv_content, headers: true, liberal_parsing: true) do |row|
      business_name = row["business_name"]&.strip
      next if business_name.blank?

      province = normalize_province(row["prov_terr"]&.strip)
      next if province.blank?

      records << {
        business_name: business_name,
        trade_name: clean(row["alt_business_name"]),
        business_number: clean(row["business_id_no"]),
        naics_code: clean(row["derived_NAICS"]),
        naics_description: clean(row["NAICS_descr"]),
        employee_size_range: clean(row["total_no_employees"]),
        address: clean(row["full_address"]),
        city: clean(row["city"]),
        province: province,
        postal_code: clean(row["postal_code"])&.upcase&.gsub(/\s+/, " "),
        latitude: parse_decimal(row["latitude"]),
        longitude: parse_decimal(row["longitude"]),
        source_system: "odbiz",
        raw_ingestion_id: raw_ingestion.id,
        created_at: Time.current,
        updated_at: Time.current
      }

      if records.size >= BATCH_SIZE
        upsert_batch!(records)
        rows_processed += records.size
        records.clear
      end
    end

    if records.any?
      upsert_batch!(records)
      rows_processed += records.size
    end

    raw_ingestion.update!(status: :complete)
    Rails.logger.info "[OdbizNormalizer] Processed #{rows_processed} business establishments for ingestion #{raw_ingestion.id}"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def extract_csv(content)
    if content.start_with?("PK")
      Zip::InputStream.open(StringIO.new(content)) do |zip|
        while (entry = zip.get_next_entry)
          return zip.read.force_encoding("UTF-8").scrub("") if entry.name.end_with?(".csv") && !entry.name.include?("MetaData") && !entry.name.include?("metadata") && !entry.name.include?("Sources") && !entry.name.include?("record-layout")
        end
      end
      raise "No CSV found in ZIP"
    else
      (+content).force_encoding("UTF-8").scrub("")
    end
  end

  def upsert_batch!(records)
    # Split records: those with BN get upserted (deduped by BN), rest get inserted
    with_bn, without_bn = records.partition { |r| r[:business_number].present? }

    if with_bn.any?
      # Deduplicate within batch — multiple establishments can share a BN
      # Keep last occurrence per BN (most recent in file order)
      deduped = with_bn.index_by { |r| r[:business_number] }.values
      BusinessEstablishment.upsert_all(
        deduped,
        unique_by: :idx_biz_est_bn_unique,
        update_only: [:business_name, :trade_name, :naics_code, :naics_description,
                       :employee_size_range, :address, :city, :province, :postal_code,
                       :latitude, :longitude, :raw_ingestion_id]
      )
    end

    if without_bn.any?
      # Records without BN can't conflict on the BN unique index, just insert
      BusinessEstablishment.insert_all(without_bn)
    end
  end

  # StatCan uses ".." for suppressed/unavailable data
  def clean(value)
    v = value&.strip
    return nil if v.blank? || v == ".."
    v
  end

  def normalize_province(raw)
    return nil if raw.blank? || raw == ".."
    CorporateNormalization::PROVINCE_MAP[raw.upcase] || raw
  end

  def parse_decimal(value)
    return nil if value.blank?
    BigDecimal(value.to_s.strip)
  rescue ArgumentError
    nil
  end
end
