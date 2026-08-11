require "zip"

class Warehouse::RawIngestion::BoundaryLoader < ActiveRecord::AssociatedObject
  BOUNDARY_TYPE_MAP = {
    "statcan_boundary_da" => "da",
    "statcan_boundary_ct" => "ct",
    "statcan_boundary_csd" => "csd",
    "statcan_boundary_fsa" => "fsa",
    "elections_canada_fed" => "fed",
    "statcan_boundary_pr" => "pr",
    "statcan_boundary_cd" => "cd",
    "statcan_boundary_er" => "er",
    "statcan_boundary_cma" => "cma",
    "statcan_boundary_popctr" => "popctr",
    "ped_ontario" => "ped",
    "ped_alberta" => "ped",
    "ped_bc" => "ped",
    "ped_quebec" => "ped",
    "ped_manitoba" => "ped",
    "ped_manitoba_wpg" => "ped",
    "ped_saskatchewan" => "ped",
    "ped_new_brunswick" => "ped",
    "ped_yukon" => "ped",
    "ped_nwt" => "ped",
    "ward_toronto" => "ward",
    "sbw_tdsb" => "school_board_ward",
    "sbw_tcdsb" => "school_board_ward",
    "sbw_viamonde" => "school_board_ward",
    "sbw_monavenir" => "school_board_ward"
  }.freeze

  # StatsCan standard field maps (used when no CUSTOM_FIELD_MAP entry exists)
  UID_FIELD_MAP = {
    "da" => "DAUID",
    "ct" => "CTUID",
    "csd" => "CSDUID",
    "fsa" => "CFSAUID",
    "pr" => "PRUID",
    "cd" => "CDUID",
    "er" => "ERUID",
    "cma" => "CMAPUID",
    "popctr" => "PCPUID"
  }.freeze

  NAME_FIELD_MAP = {
    "da" => "DAUID",
    "ct" => "CTNAME",
    "csd" => "CSDNAME",
    "fsa" => "CFSAUID",
    "pr" => "PRENAME",
    "cd" => "CDNAME",
    "er" => "ERNAME",
    "cma" => "CMANAME",
    "popctr" => "PCNAME"
  }.freeze

  FR_NAME_FIELD_MAP = {
    "pr" => "PRFNAME",
    "er" => "ERNAME"
  }.freeze

  # Sources with non-standard field names (PED, wards, school districts)
  # source_srid: EPSG code for projected shapefiles that need reprojection to WGS84
  CUSTOM_FIELD_MAP = {
    "elections_canada_fed" => { uid: "FED_NUM", name_en: "ED_NAMEE", name_fr: "ED_NAMEF",
                                province_from_uid: true, source_srid: 3347 },
    "ped_ontario" => { uid: "ED_ID", name_en: "ENGLISH_NA", name_fr: "FRENCH_NAM" },
    "ped_alberta" => { uid: "EDNumber20", name_en: "EDName2017", name_fr: nil },
    "ped_bc" => { uid: "ED_ABBREVI", name_en: "ED_NAME", name_fr: nil },
    "ped_quebec" => { uid: "CO_CEP", name_en: "NM_CEP", name_fr: "NM_CEP",
                       province_code: "24", source_srid: 32198 },
    "ped_manitoba" => { uid: "ED", name_en: "ED", name_fr: "ED_French",
                         province_code: "46", source_srid: 32614 },
    "ped_manitoba_wpg" => { uid: "ED", name_en: "ED", name_fr: "ED_French",
                             province_code: "46", source_srid: 32614 },
    "ped_saskatchewan" => { uid: "Number", name_en: "Name", name_fr: nil,
                             province_code: "47", source_srid: 32613 },
    "ped_new_brunswick" => { uid: "dist_id", name_en: "ped_name_e", name_fr: "ped_name_f",
                              province_code: "13" },
    "ped_yukon" => { uid: "ELECT_NAME", name_en: "ELECT_NAME", name_fr: "FR_ELECNAM",
                      province_code: "60", source_srid: 3578 },
    "ped_nwt" => { uid: "ED", name_en: "ED", name_fr: nil,
                    province_code: "61", source_srid: 3580 },
    # AREA_S_CD is only the zero-padded ward number, "01"–"25", and the unique
    # index is (boundary_type, geo_uid, census_year) — so the next city's ward
    # layer would collide on "01" and upsert over Toronto's ward 1. Prefixing
    # with the municipality's CSD uid keeps ward uids unique per city and
    # readable ("3520005-19"); Warehouse::BoundaryLookup reads the ward number
    # back off the last segment.
    "ward_toronto" => { uid: "AREA_S_CD", name_en: "AREA_NAME", name_fr: nil, province_code: "35",
                         uid_prefix: "3520005-" },
    "sbw_tdsb" => { uid: "AREA_NAME", name_en: "AREA_NAME", name_fr: nil, province_code: "35",
                     uid_prefix: "TDSB-", name_prefix: "TDSB Ward " },
    "sbw_tcdsb" => { uid: "AREA_NAME", name_en: "AREA_NAME", name_fr: nil, province_code: "35",
                      uid_prefix: "TCDSB-", name_prefix: "TCDSB Ward " },
    "sbw_viamonde" => { uid: "AREA_NAME", name_en: "AREA_NAME", name_fr: "AREA_NAME", province_code: "35",
                         uid_prefix: "VIAMONDE-", name_prefix: "Viamonde – " },
    "sbw_monavenir" => { uid: "AREA_NAME", name_en: "AREA_NAME", name_fr: "AREA_NAME", province_code: "35",
                          uid_prefix: "MONAVENIR-", name_prefix: "MonAvenir – " }
  }.freeze

  WGS84_SRID = 4326
  # Every boundary file loaded here is from the 2021 Census.
  CENSUS_YEAR = 2021

  # StatCan ships its boundary files in NAD83 / Statistics Canada Lambert
  # (EPSG:3347, metres) rather than lat/long — see the .prj in any of the
  # archives — so they need the same reprojection to WGS84 that the federal
  # riding file declares for itself. Without it the coordinates are metres
  # stored as degrees and every polygon is nonsense.
  STATCAN_LAMBERT_SRID = 3347
  STATCAN_SOURCE_PREFIX = "statcan_boundary_".freeze

  def load(file_content:)
    boundary_type = detect_boundary_type
    return fail_ingestion("Unknown boundary type for source: #{raw_ingestion.source.name}") unless boundary_type

    Dir.mktmpdir do |tmpdir|
      extract_shapefile(file_content, tmpdir)
      shp_path = Dir.glob(File.join(tmpdir, "**/*.shp")).first
      return fail_ingestion("No .shp file found in archive") unless shp_path

      import_shapefile(shp_path, boundary_type)
    end

    raw_ingestion.update!(status: :complete)
  rescue => e
    fail_ingestion(e.message)
    raise
  end

  private

  def detect_boundary_type
    BOUNDARY_TYPE_MAP[raw_ingestion.source.name]
  end

  def extract_shapefile(content, tmpdir)
    zip_path = File.join(tmpdir, "archive.zip")
    File.binwrite(zip_path, content)

    Zip::File.open(zip_path) do |zip|
      zip.each do |entry|
        next if entry.directory?
        dest = File.join(tmpdir, File.basename(entry.name))
        File.binwrite(dest, entry.get_input_stream.read)
      end
    end
  end

  def import_shapefile(shp_path, boundary_type)
    source_name = raw_ingestion.source.name
    custom = CUSTOM_FIELD_MAP[source_name]
    uid_field = custom&.[](:uid) || UID_FIELD_MAP[boundary_type]
    name_en_field = custom&.[](:name_en) || NAME_FIELD_MAP[boundary_type]
    name_fr_field = custom&.[](:name_fr)
    fixed_province = custom&.[](:province_code)
    source_srid = custom&.[](:source_srid) ||
      (STATCAN_LAMBERT_SRID if source_name.start_with?(STATCAN_SOURCE_PREFIX))
    factory = if source_srid
      RGeo::Geos.factory(srid: source_srid, proj4: "EPSG:#{source_srid}")
    else
      RGeo::Cartesian.simple_factory(srid: WGS84_SRID)
    end
    wgs84_factory = source_srid ? RGeo::Geos.factory(srid: WGS84_SRID, proj4: "EPSG:#{WGS84_SRID}") : nil
    records = []
    skipped = 0

    RGeo::Shapefile::Reader.open(shp_path, factory: factory) do |file|
      file.num_records.times do |i|
        record = begin
          file.get(i)
        rescue RGeo::Error::InvalidGeometry
          skipped += 1
          next
        end
        next unless record

        geo_uid = record[uid_field]&.to_s&.strip
        next unless geo_uid.present?
        geo_uid = "#{custom[:uid_prefix]}#{geo_uid}" if custom&.[](:uid_prefix)

        geometry = normalize_geometry(record.geometry)
        geometry = reproject(geometry, wgs84_factory) if geometry && source_srid
        next unless geometry

        province_code = if fixed_province
          fixed_province
        elsif custom&.[](:province_from_uid)
          geo_uid[0, 2]
        else
          extract_province_code(record, boundary_type)
        end

        raw_name = record[name_en_field]&.to_s&.strip
        name_en = custom&.[](:name_prefix) ? "#{custom[:name_prefix]}#{raw_name}" : raw_name
        name_fr = if name_fr_field
          raw_fr = record[name_fr_field]&.strip
          custom&.[](:name_prefix) ? "#{custom[:name_prefix]}#{raw_fr}" : raw_fr
        elsif custom.nil?
          extract_fr_name(record, boundary_type, NAME_FIELD_MAP[boundary_type])
        end

        records << {
          boundary_type: boundary_type,
          geo_uid: geo_uid,
          name_en: name_en,
          name_fr: name_fr,
          province_code: province_code,
          # upsert_all writes straight to the table, so GeoBoundary's
          # default_code_system callback never runs and the NOT NULL column
          # has to be filled here. Same derivation as the model's.
          code_system: "#{boundary_type}_#{CENSUS_YEAR}",
          geometry: geometry,
          area_sq_km: record["LANDAREA"]&.to_f,
          census_year: CENSUS_YEAR,
          raw_ingestion_id: raw_ingestion.id
        }
      end
    end

    Warehouse::GeoBoundary.upsert_all(
      records,
      unique_by: :idx_geo_boundaries_unique,
      update_only: [ :name_en, :name_fr, :province_code, :geometry, :area_sq_km, :raw_ingestion_id ]
    ) if records.any?

    Rails.logger.info "[BoundaryLoader] Loaded #{records.size} #{boundary_type} boundaries (#{skipped} skipped due to invalid geometry)"
  end

  def extract_province_code(record, _boundary_type)
    record["PRUID"]&.strip
  end

  def extract_fr_name(record, boundary_type, name_field)
    if FR_NAME_FIELD_MAP[boundary_type]
      record[FR_NAME_FIELD_MAP[boundary_type]]&.strip
    else
      record["#{name_field.sub(/NAME$/, 'NOM')}"]&.strip
    end
  end

  def reproject(geom, target_factory)
    RGeo::Feature.cast(geom, factory: target_factory, project: true)
  end

  def normalize_geometry(geom)
    case geom
    when RGeo::Feature::MultiPolygon
      geom
    when RGeo::Feature::Polygon
      geom.factory.multi_polygon([ geom ])
    else
      nil
    end
  end

  def fail_ingestion(message)
    raw_ingestion.update!(status: :failed, error_message: message)
  end
end
