class RawIngestion::RelationshipLoader < ActiveRecord::AssociatedObject
  # StatsCan geographic relationship file maps DAs to parent geographies:
  # DAUID, CTUID, CSDUID, CFSAUID, etc.
  RELATIONSHIP_COLUMNS = {
    "CTUID" => "da_ct",
    "CSDUID" => "da_csd",
    "CFSAUID" => "da_fsa"
  }.freeze

  def load(csv_content:)
    rows = CSV.parse(csv_content, headers: true, liberal_parsing: true)
    records = []

    # Pre-load DA and parent boundary IDs for fast lookup
    da_index = GeoBoundary.by_type(:da).pluck(:geo_uid, :id).to_h
    parent_indices = RELATIONSHIP_COLUMNS.each_with_object({}) do |(col, type), hash|
      parent_type = type.sub("da_", "")
      hash[col] = GeoBoundary.by_type(parent_type).pluck(:geo_uid, :id).to_h
    end

    rows.each do |row|
      da_uid = row["DAUID"]&.strip
      da_id = da_index[da_uid]
      next unless da_id

      RELATIONSHIP_COLUMNS.each do |col, rel_type|
        parent_uid = row[col]&.strip
        next if parent_uid.blank?

        parent_id = parent_indices[col][parent_uid]
        next unless parent_id

        records << {
          da_id: da_id,
          parent_id: parent_id,
          relationship_type: rel_type,
          raw_ingestion_id: raw_ingestion.id
        }
      end
    end

    GeoRelationship.upsert_all(
      records,
      unique_by: :idx_geo_relationships_unique,
      update_only: [ :raw_ingestion_id ]
    ) if records.any?

    raw_ingestion.update!(status: :complete)
    Rails.logger.info "[RelationshipLoader] Loaded #{records.size} relationships"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end
end
