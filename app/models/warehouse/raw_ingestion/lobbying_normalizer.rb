class Warehouse::RawIngestion::LobbyingNormalizer < ActiveRecord::AssociatedObject
  performs :normalize

  def normalize(csv_content:)
    rows_processed = 0
    rows_skipped = 0
    resolver = Warehouse::Organization.new.entity_resolver

    CSV.parse(csv_content, headers: true, liberal_parsing: true) do |row|
      begin
        lobbyist = find_or_create_lobbyist(row)

        # Resolve the government institution being lobbied
        govt_institution = row["Government Institution"]&.strip || row["institution"]&.strip
        org = nil
        lineage = nil

        if govt_institution.present?
          result = resolver.resolve(name: govt_institution, raw_ingestion: raw_ingestion)
          org = result.organization
          lineage = result.lineage_entry
        end

        Warehouse::LobbyingActivity.create!(
          lobbyist: lobbyist,
          organization: org,
          client_name: row["Client"]&.strip || row["client_name"]&.strip,
          subject_matter: row["Subject Matter"]&.strip || row["subject_matter"]&.strip,
          start_date: parse_date(row["Start Date"] || row["start_date"]),
          end_date: parse_date(row["End Date"] || row["end_date"]),
          status: row["Status"]&.strip&.downcase || "active",
          raw_ingestion: raw_ingestion,
          lineage_entry: lineage
        )

        rows_processed += 1
      rescue => e
        rows_skipped += 1
        Rails.logger.error "[LobbyingNormalizer] Error on row: #{e.message}"
      end
    end

    status = rows_skipped > 0 ? :partial : :complete
    raw_ingestion.update!(status: status)

    Rails.logger.info "[LobbyingNormalizer] Processed #{rows_processed}, skipped #{rows_skipped} for ingestion #{raw_ingestion.id}"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end

  private

  def find_or_create_lobbyist(row)
    name = row["Lobbyist Name"]&.strip || row["name"]&.strip
    reg_num = row["Registration Number"]&.strip || row["registration_number"]&.strip
    lobbyist_type = row["Type"]&.strip&.downcase || row["lobbyist_type"]&.strip

    if reg_num.present?
      Warehouse::Lobbyist.find_or_create_by!(registration_number: reg_num) do |l|
        l.name = name || "Unknown"
        l.lobbyist_type = lobbyist_type
      end
    else
      Warehouse::Lobbyist.find_or_create_by!(name: name || "Unknown") do |l|
        l.lobbyist_type = lobbyist_type
      end
    end
  end

  def parse_date(value)
    return nil if value.blank?
    Date.parse(value.to_s.strip)
  rescue Date::Error
    nil
  end
end
