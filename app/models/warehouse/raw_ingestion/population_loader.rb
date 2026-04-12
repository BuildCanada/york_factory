class RawIngestion::PopulationLoader < ActiveRecord::AssociatedObject
  def load(csv_content:)
    rows = CSV.parse(csv_content, headers: true, liberal_parsing: true)
    updates = []

    rows.each do |row|
      da_uid = row["DAUID"]&.strip || row["ALT_GEO_CODE"]&.strip
      population = row["POPULATION"]&.strip&.to_i || row["T_DATA_DONNEE"]&.strip&.to_i
      next unless da_uid.present? && population && population > 0

      updates << { geo_uid: da_uid, population: population }
    end

    if updates.empty?
      Rails.logger.warn "[PopulationLoader] No valid population rows found in CSV"
      raw_ingestion.update!(status: :complete)
      return
    end

    # Bulk update using sanitized bind parameters
    updates.each_slice(5000) do |batch|
      placeholders = batch.map { "(?, ?)" }.join(", ")
      binds = batch.flat_map { |u| [ u[:geo_uid], u[:population].to_i ] }

      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL, *binds
          UPDATE warehouse.geo_boundaries
          SET population = vals.population, updated_at = NOW()
          FROM (VALUES #{placeholders}) AS vals(geo_uid, population)
          WHERE warehouse.geo_boundaries.geo_uid = vals.geo_uid
            AND warehouse.geo_boundaries.boundary_type = 'da'
            AND warehouse.geo_boundaries.census_year = 2021
        SQL
      ])

      ActiveRecord::Base.connection.execute(sql)
    end

    raw_ingestion.update!(status: :complete)
    Rails.logger.info "[PopulationLoader] Updated population for #{updates.size} DAs"
  rescue => e
    raw_ingestion.update!(status: :failed, error_message: e.message)
    raise
  end
end
