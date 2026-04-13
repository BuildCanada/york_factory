namespace :geo do
  desc "Build all crosswalk tables from geo_boundaries, geo_relationships, and spatial joins"
  task build_crosswalk: :environment do
    puts "Building crosswalks..."

    ActiveRecord::Base.transaction do
      build_tabular_crosswalks
      build_spatial_crosswalks
    end

    puts "Done. #{Warehouse::GeoCrosswalk.count} crosswalk entries created."
  end

  desc "Run full geo pipeline: fetch boundaries, relationships, population, then build crosswalks"
  task pipeline: :environment do
    boundary_sources = Warehouse::Source.where(
      "name LIKE 'statcan_boundary_%' OR name LIKE 'elections_canada_%' OR name LIKE 'ped_%' OR name LIKE 'ward_%' OR name LIKE 'sbw_%'"
    ).where.not(name: "ped_ontario")
    boundary_sources.each do |source|
      puts "Fetching #{source.name}..."
      source.fetcher.fetch
    end

    rel_source = Warehouse::Source.find_by(name: "statcan_geo_relationship")
    if rel_source
      puts "Fetching geo relationships..."
      rel_source.fetcher.fetch
    end

    pop_source = Warehouse::Source.find_by(name: "statcan_da_population")
    if pop_source
      puts "Fetching DA populations..."
      pop_source.fetcher.fetch
    end

    Rake::Task["geo:build_crosswalk"].invoke
  end
end

def build_tabular_crosswalks
  # For each pair of parent boundary types linked through DAs,
  # compute population-weighted crosswalks.
  #
  # e.g., FSA↔CT: find all DAs that belong to both an FSA and a CT,
  # group by (FSA, CT), sum DA populations.
  pairs = [
    %w[da_fsa da_ct fsa ct],
    %w[da_fsa da_csd fsa csd],
    %w[da_ct da_csd ct csd]
  ]

  pairs.each do |rel_a, rel_b, type_a, type_b|
    puts "  Tabular crosswalk: #{type_a} ↔ #{type_b}"
    rows = crosswalk_query(rel_a, rel_b, type_a, type_b)
    insert_crosswalks(rows)
  end
end

def build_spatial_crosswalks
  # DA centroid point-in-polygon against FED/PED boundaries.
  # Then aggregate DA→parent relationships to compute crosswalks
  # for all boundary types against FED and PED.
  %w[fed ped].each do |spatial_type|
    puts "  Spatial assignment: DA → #{spatial_type}"

    # First, assign DAs to FED/PED via centroid containment
    assignment_sql = ActiveRecord::Base.sanitize_sql_array([
      <<~SQL, spatial_type
        SELECT da.id AS da_id, parent.id AS parent_id
        FROM warehouse.geo_boundaries da
        JOIN warehouse.geo_boundaries parent
          ON ST_Contains(parent.geometry::geometry, ST_Centroid(da.geometry::geometry))
        WHERE da.boundary_type = 'da'
          AND parent.boundary_type = ?
      SQL
    ])

    assignments = ActiveRecord::Base.connection.execute(assignment_sql)

    # Store as temporary relationships for crosswalk computation
    records = assignments.map do |row|
      {
        da_id: row["da_id"],
        parent_id: row["parent_id"],
        relationship_type: "da_#{spatial_type}"
      }
    end

    Warehouse::GeoRelationship.upsert_all(records, unique_by: :idx_geo_relationships_unique) if records.any?

    # Now build crosswalks from every other type to this spatial type
    %w[fsa ct csd].each do |other_type|
      rel_other = "da_#{other_type}"
      puts "    Crosswalk: #{other_type} ↔ #{spatial_type}"
      rows = crosswalk_query(rel_other, "da_#{spatial_type}", other_type, spatial_type)
      insert_crosswalks(rows)
    end

    # FED ↔ PED crosswalk (both spatial types against each other)
    other_spatial = spatial_type == "fed" ? "ped" : "fed"
    if Warehouse::GeoBoundary.by_type(other_spatial).exists?
      puts "    Crosswalk: #{other_spatial} ↔ #{spatial_type}"
      rows = crosswalk_query("da_#{other_spatial}", "da_#{spatial_type}", other_spatial, spatial_type)
      insert_crosswalks(rows)
    end
  end
end

def crosswalk_query(rel_a, rel_b, type_a, type_b)
  sql = ActiveRecord::Base.sanitize_sql_array([
    <<~SQL, type_a, type_b, rel_a, rel_b
      SELECT
        ra.parent_id AS source_id,
        rb.parent_id AS target_id,
        ? AS source_type,
        ? AS target_type,
        SUM(COALESCE(da.population, 0)) AS overlap_population,
        COUNT(DISTINCT da.id) AS da_count
      FROM warehouse.geo_relationships ra
      JOIN warehouse.geo_relationships rb ON ra.da_id = rb.da_id
      JOIN warehouse.geo_boundaries da ON da.id = ra.da_id
      WHERE ra.relationship_type = ?
        AND rb.relationship_type = ?
      GROUP BY ra.parent_id, rb.parent_id
      HAVING SUM(COALESCE(da.population, 0)) > 0
    SQL
  ])

  ActiveRecord::Base.connection.execute(sql)
end

def insert_crosswalks(rows)
  records = rows.map do |row|
    {
      source_id: row["source_id"],
      target_id: row["target_id"],
      source_type: row["source_type"],
      target_type: row["target_type"],
      overlap_population: row["overlap_population"],
      da_count: row["da_count"],
      census_year: 2021
    }
  end

  return if records.empty?

  # Group by source/target to compute population-weighted crosswalk values
  source_totals = records.group_by { |r| r[:source_id] }
    .transform_values { |rs| rs.sum { |r| r[:overlap_population].to_i } }

  target_totals = records.group_by { |r| r[:target_id] }
    .transform_values { |rs| rs.sum { |r| r[:overlap_population].to_i } }

  records.each do |r|
    source_pop = source_totals[r[:source_id]].to_f
    target_pop = target_totals[r[:target_id]].to_f
    overlap = r[:overlap_population].to_i

    r[:weight_source_to_target] = source_pop > 0 ? (overlap / source_pop).round(8) : 0
    r[:weight_target_to_source] = target_pop > 0 ? (overlap / target_pop).round(8) : 0
  end

  Warehouse::GeoCrosswalk.upsert_all(records, unique_by: :idx_geo_crosswalks_unique)
  puts "    → #{records.size} crosswalk entries"
end
