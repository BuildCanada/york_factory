class RawIngestion::OdaNormalizer < ActiveRecord::AssociatedObject
  performs :normalize

  BATCH_SIZE = 5_000

  # Real ODA CSV columns (Statistics Canada Open Database of Addresses):
  # latitude, longitude, source_id, id, group_id, street_no, street, str_name,
  # str_type, str_dir, unit, city, postal_code, full_addr, city_pcs,
  # str_name_pcs, str_type_pcs, str_dir_pcs, csduid, csdname, pruid, provider

  # PRUID → province abbreviation mapping
  PRUID_MAP = {
    "10" => "NL", "11" => "PE", "12" => "NS", "13" => "NB",
    "24" => "QC", "35" => "ON", "46" => "MB", "47" => "SK",
    "48" => "AB", "59" => "BC", "60" => "YT", "61" => "NT", "62" => "NU"
  }.freeze

  def normalize(file_content:)
    records = []
    rows_processed = 0

    csv_content = extract_csv(file_content)

    # Strip BOM
    bom = +"\xEF\xBB\xBF"
    bom.force_encoding("UTF-8")
    csv_content.sub!(bom, "")

    CSV.parse(csv_content, headers: true, liberal_parsing: true) do |row|
      full_address = row["full_addr"]&.strip
      city = row["city"]&.strip || row["csdname"]&.strip
      province = resolve_province(row)
      postal_code = row["postal_code"]&.strip

      next if city.blank? || province.blank?
      # full_address and postal_code may be blank in ODA — don't skip, use what we have
      next if full_address.blank? && postal_code.blank?

      # Build full_address from components if missing
      if full_address.blank?
        parts = [row["street_no"]&.strip, row["street"]&.strip].compact
        full_address = parts.join(" ").presence
        next if full_address.blank?
      end

      source_id = row["source_id"]&.strip || row["id"]&.strip
      next if source_id.blank?

      records << {
        full_address: full_address,
        street_name: row["str_name"]&.strip,
        street_number: row["street_no"]&.strip,
        unit_number: row["unit"]&.strip,
        city: city,
        province: province,
        postal_code: postal_code&.upcase&.gsub(/\s+/, " ") || "",
        country: "CA",
        latitude: parse_decimal(row["latitude"]),
        longitude: parse_decimal(row["longitude"]),
        census_subdivision_name: row["csdname"]&.strip,
        census_subdivision_type: nil, # Not in ODA v1
        source_id: source_id,
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
    Rails.logger.info "[OdaNormalizer] Processed #{rows_processed} addresses for ingestion #{raw_ingestion.id}"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def extract_csv(content)
    if content.start_with?("PK")
      Zip::InputStream.open(StringIO.new(content)) do |zip|
        while (entry = zip.get_next_entry)
          next if entry.name.include?("MetaData") || entry.name.include?("metadata") ||
                  entry.name.include?("Sources") || entry.name.include?("Data_Sources")
          return zip.read.force_encoding("UTF-8").scrub("") if entry.name.end_with?(".csv")
        end
      end
      raise "No CSV found in ZIP"
    else
      (+content).force_encoding("UTF-8").scrub("")
    end
  end

  def resolve_province(row)
    # Try pruid (numeric code used in real ODA data)
    pruid = row["pruid"]&.strip
    return PRUID_MAP[pruid] if pruid.present? && PRUID_MAP[pruid]

    # Fallback to text province columns
    raw = row["province"]&.strip || row["prname"]&.strip
    return nil if raw.blank?
    CorporateNormalization::PROVINCE_MAP[raw.upcase] || raw
  end

  def upsert_batch!(records)
    StandardizedAddress.upsert_all(
      records,
      unique_by: :source_id,
      update_only: [:full_address, :street_name, :street_number, :unit_number,
                     :city, :province, :postal_code, :latitude, :longitude,
                     :census_subdivision_name, :census_subdivision_type,
                     :raw_ingestion_id]
    )
  end

  def parse_decimal(value)
    return nil if value.blank?
    BigDecimal(value.to_s.strip)
  rescue ArgumentError
    nil
  end
end
