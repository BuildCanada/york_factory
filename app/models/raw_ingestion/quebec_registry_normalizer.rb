class RawIngestion::QuebecRegistryNormalizer < ActiveRecord::AssociatedObject
  include CorporateNormalization

  performs :normalize

  # Quebec Données Québec CSV format:
  # ZIP contains 6 CSV files keyed by NEQ (Numéro d'entreprise du Québec)
  # Main file: entreprises.csv
  # Supplementary: noms.csv, adresses.csv, activites.csv, etc.

  def normalize(file_content:)
    records = []
    rows_processed = 0

    entreprises = {}
    noms = {}
    adresses = {}

    Zip::InputStream.open(StringIO.new(file_content)) do |zip|
      while (entry = zip.get_next_entry)
        csv_content = zip.read.force_encoding("UTF-8").scrub("")

        case entry.name.downcase
        when /entreprises/
          parse_entreprises(csv_content, entreprises)
        when /noms/
          parse_noms(csv_content, noms)
        when /adresses/
          parse_adresses(csv_content, adresses)
        end
      end
    end

    # Merge and create records
    entreprises.each do |neq, data|
      name_data = noms[neq]
      addr_data = adresses[neq]

      legal_name = name_data&.first&.dig(:name) || data[:name]
      next if legal_name.blank?

      record = {
        jurisdiction: "qc",
        registry_id: neq,
        legal_name: normalize_name(legal_name),
        corporation_type: data[:type],
        status: normalize_status(data[:status]),
        registered_office_address: addr_data&.first&.dig(:address),
        registered_office_province: "QC",
        registered_office_postal_code: addr_data&.first&.dig(:postal_code),
        incorporation_date: data[:constitution_date],
        source_system: "quebec_req",
        raw_ingestion_id: raw_ingestion.id,
        created_at: Time.current,
        updated_at: Time.current
      }

      records << record

      if records.size >= BATCH_SIZE
        batch_upsert!(records.dup)
        rows_processed += records.size
        records.clear
      end
    end

    if records.any?
      batch_upsert!(records)
      rows_processed += records.size
    end

    # Create aliases from additional names
    create_aliases(noms)

    raw_ingestion.update!(status: :complete)
    Rails.logger.info "[QuebecRegistryNormalizer] Processed #{rows_processed} QC corps for ingestion #{raw_ingestion.id}"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def parse_entreprises(csv_content, entreprises)
    CSV.parse(csv_content, headers: true, liberal_parsing: true) do |row|
      neq = row["NEQ"]&.strip
      next if neq.blank?

      entreprises[neq] = {
        name: row["NOM_ENTREP"]&.strip || row["Nom"]&.strip,
        type: row["FORME_JURIDIQUE"]&.strip || row["Type"]&.strip,
        status: row["ETAT"]&.strip || row["État"]&.strip,
        constitution_date: parse_date(row["DATE_CONST"]&.strip || row["Date constitution"]&.strip)
      }
    end
  end

  def parse_noms(csv_content, noms)
    CSV.parse(csv_content, headers: true, liberal_parsing: true) do |row|
      neq = row["NEQ"]&.strip
      next if neq.blank?

      noms[neq] ||= []
      noms[neq] << {
        name: row["NOM"]&.strip || row["Nom"]&.strip,
        type: row["TYPE_NOM"]&.strip
      }
    end
  end

  def parse_adresses(csv_content, adresses)
    CSV.parse(csv_content, headers: true, liberal_parsing: true) do |row|
      neq = row["NEQ"]&.strip
      next if neq.blank?

      adresses[neq] ||= []
      adresses[neq] << {
        address: [row["ADRESSE"]&.strip, row["VILLE"]&.strip].compact.join(", "),
        postal_code: row["CODE_POSTAL"]&.strip
      }
    end
  end

  def create_aliases(noms)
    noms.each do |neq, names|
      corp = CorporateEntity.find_by(jurisdiction: "qc", registry_id: neq)
      next unless corp

      names.each do |name_data|
        next if name_data[:name].blank?
        corp.corporate_entity_aliases.find_or_create_by!(alias_name: normalize_name(name_data[:name]))
      end
    end
  end

  def parse_date(text)
    return nil if text.blank?
    Date.parse(text)
  rescue Date::Error, ArgumentError
    nil
  end
end
