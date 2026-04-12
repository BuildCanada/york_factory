require "zip"

class RawIngestion::AddressLoader < ActiveRecord::AssociatedObject
  def load(file_content:)
    Dir.mktmpdir do |tmpdir|
      csv_content = extract_csv(file_content, tmpdir)
      return fail_ingestion("No CSV file found in archive") unless csv_content

      import_addresses(csv_content)
    end

    raw_ingestion.update!(status: :complete)
  rescue => e
    fail_ingestion(e.message)
    raise
  end

  private

  def extract_csv(content, tmpdir)
    zip_path = File.join(tmpdir, "archive.zip")
    File.binwrite(zip_path, content)

    Zip::File.open(zip_path) do |zip|
      entry = zip.entries.find { |e| e.name.end_with?(".csv") && !e.name.include?("Data_Sources") && !e.name.include?("metadata") }
      return nil unless entry
      entry.get_input_stream.read
    end
  end

  def import_addresses(csv_content)
    rows = CSV.parse(csv_content, headers: true, liberal_parsing: true)
    total = 0

    rows.each_slice(5000) do |batch|
      records = batch.filter_map do |row|
        oda_uid = row["id"]&.strip
        next unless oda_uid.present?

        pruid = row["pruid"]&.strip
        {
          oda_uid: oda_uid,
          street_number: row["street_no"]&.strip,
          street_name: row["str_name"]&.strip,
          street_type: row["str_type"]&.strip,
          street_direction: row["str_dir"]&.strip,
          unit: row["unit"]&.strip,
          city: row["city"]&.strip,
          province_code: pruid,
          postal_code: row["postal_code"]&.strip,
          full_address: row["full_addr"]&.strip,
          csd_uid: row["csduid"]&.strip,
          csd_name: row["csdname"]&.strip,
          latitude: row["latitude"]&.to_f,
          longitude: row["longitude"]&.to_f,
          provider: row["provider"]&.strip,
          raw_ingestion_id: raw_ingestion.id
        }
      end

      Address.upsert_all(
        records,
        unique_by: :idx_addresses_oda_uid,
        update_only: [ :street_number, :street_name, :street_type, :street_direction,
                      :unit, :city, :province_code, :postal_code, :full_address,
                      :csd_uid, :csd_name, :latitude, :longitude, :provider, :raw_ingestion_id ]
      ) if records.any?

      total += records.size
    end

    Rails.logger.info "[AddressLoader] Loaded #{total} addresses"
  end

  def fail_ingestion(message)
    raw_ingestion.update!(status: :failed, error_message: message)
  end
end
