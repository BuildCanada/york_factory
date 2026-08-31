require "json"

class Warehouse::InstitutionRelease::CsdAuthorityImporter
  class ImportError < StandardError; end

  EXPECTED_2021_CSD_COUNT = 5_161
  AUTHORITY_ROLES = %w[governs administers].freeze
  ON_RESERVE_TYPES = %w[IRI S-É IGD TC TK NL TWL TAL].freeze
  INDIGENOUS_AUTHORITY_TYPES = {
    "24" => %w[TI],
    "60" => %w[SG]
  }.freeze
  PROVINCE_NAMESPACES = {
    "10" => "nl", "11" => "pe", "12" => "ns", "13" => "nb", "24" => "qc",
    "35" => "on", "46" => "mb", "47" => "sk", "48" => "ab", "59" => "bc",
    "60" => "yt", "61" => "nt", "62" => "nu"
  }.freeze

  def initialize(release:, inventory_path:, authority_paths: [])
    @release = release
    @inventory_path = Pathname(inventory_path)
    @authority_paths = Array(authority_paths).compact_blank.map { |path| Pathname(path) }
  end

  def import!
    inventory = JSON.parse(@inventory_path.read)
    validate_inventory!(inventory)
    crosswalks = @authority_paths.map { |path| JSON.parse(path.read) }
    validate_crosswalks!(crosswalks)

    Warehouse::Record.transaction do
      geography_source = import_inventory_source!(inventory.fetch("source"))
      import_csd_snapshots!(inventory.fetch("csds"))
      crosswalk_sources = import_crosswalk_sources!(crosswalks)
      import_crosswalk_mappings!(crosswalks, crosswalk_sources, geography_source)
      resolve_authority_statuses!
      import_coverage!(geography_source)
      validate_complete_inventory!
    end
  rescue Errno::ENOENT, JSON::ParserError, KeyError, Date::Error, ArgumentError,
    ActiveRecord::ActiveRecordError => error
    raise ImportError, error.message
  end

  private

  def validate_inventory!(payload)
    raise ImportError, "CSD inventory release does not match" unless payload.fetch("release_version") == @release.version
    unless Integer(payload.fetch("geography_vintage")) == @release.geography_vintage
      raise ImportError, "CSD inventory geography vintage does not match"
    end
    rows = payload.fetch("csds")
    expected = Integer(payload.fetch("expected_csd_count"))
    raise ImportError, "CSD inventory expected count mismatch" unless expected == expected_count
    raise ImportError, "CSD inventory contains #{rows.length}, expected #{expected}" unless rows.length == expected
    raise ImportError, "duplicate CSD UIDs" unless rows.map { |row| row.fetch("geo_uid") }.uniq.length == rows.length
  end

  def validate_crosswalks!(payloads)
    payloads.each do |payload|
      raise ImportError, "authority crosswalk release does not match" unless payload.fetch("release_version") == @release.version
      unless Integer(payload.fetch("geography_vintage")) == @release.geography_vintage
        raise ImportError, "authority crosswalk geography vintage does not match"
      end
      Array(payload["mappings"]).each do |row|
        raise ImportError, "invalid authority role" unless AUTHORITY_ROLES.include?(row.fetch("role"))
        raise ImportError, "authority mapping requires a CSD UID" if row.fetch("csd_uid").blank?
        raise ImportError, "authority mapping requires an institution ID" if row.fetch("institution_id").blank?
      end
    end
  end

  def import_inventory_source!(row)
    canonical_id = row.fetch("canonical_id")
    @release.institution_sources.find_by(canonical_id: canonical_id) ||
      Warehouse::InstitutionSource.create!(
        institution_release: @release,
        canonical_id: canonical_id,
        publisher_name: row.fetch("publisher_name"),
        title_en: row.fetch("title_en"),
        title_fr: row["title_fr"],
        url: row.fetch("url"),
        retrieved_at: Time.iso8601(JSON.parse(@inventory_path.read).fetch("retrieved_at")),
        license: row["license"],
        languages: row.fetch("languages")
      )
  end

  def import_csd_snapshots!(rows)
    rows.each do |row|
      uid = row.fetch("geo_uid").to_s
      canonical_id = Warehouse::InstitutionGeographySnapshot.canonical_id_for(
        boundary_type: "csd", census_year: @release.geography_vintage, geo_uid: uid
      )
      snapshot = @release.institution_geography_snapshots.find_or_initialize_by(canonical_id: canonical_id)
      attributes = {
        code_system: "csd_#{@release.geography_vintage}",
        geo_uid: uid,
        boundary_type: "csd",
        classification_type: row.fetch("classification_type"),
        name_en: row.fetch("name_en"),
        name_fr: row["name_fr"],
        province_code: row.fetch("province_code"),
        census_year: @release.geography_vintage,
        area_sq_km: row["area_sq_km"],
        authority_status: snapshot.new_record? ? "unresolved" : snapshot.authority_status
      }
      if snapshot.new_record?
        snapshot.assign_attributes(attributes)
        snapshot.save!
      else
        # This runs inside the still-uncommitted national build transaction. Release records become immutable at commit.
        snapshot.update_columns(attributes.merge(updated_at: Time.current))
      end
    end
  end

  def import_crosswalk_sources!(crosswalks)
    crosswalks.to_h do |payload|
      sources = Array(payload["sources"]).to_h do |row|
        key = row.fetch("key")
        source = @release.institution_sources.find_by(canonical_id: row.fetch("canonical_id")) ||
          Warehouse::InstitutionSource.create!(
            institution_release: @release,
            canonical_id: row.fetch("canonical_id"),
            publisher_name: row.fetch("publisher_name"),
            title_en: row.fetch("title_en"),
            title_fr: row["title_fr"],
            url: row.fetch("url"),
            retrieved_at: Time.iso8601(row.fetch("retrieved_at")),
            license: row["license"],
            languages: row.fetch("languages")
          )
        [ key, source ]
      end
      [ payload.object_id, sources ]
    end
  end

  def import_crosswalk_mappings!(crosswalks, sources, fallback_source)
    crosswalks.each do |payload|
      payload_sources = sources.fetch(payload.object_id)
      Array(payload["mappings"]).each do |row|
        geography = @release.institution_geography_snapshots.find_by!(
          boundary_type: "csd", census_year: @release.geography_vintage, geo_uid: row.fetch("csd_uid").to_s
        )
        institution = @release.institutions.find_by!(canonical_id: row.fetch("institution_id"))
        source = row["source_key"] ? payload_sources.fetch(row.fetch("source_key")) : fallback_source
        link = @release.institution_geographies.find_or_initialize_by(
          institution: institution, institution_geography_snapshot: geography, role: row.fetch("role")
        )
        attributes = {
          institution_source: source,
          match_method: row.fetch("match_method", "authoritative_crosswalk"),
          confidence: row.fetch("confidence", 1.0),
          valid_from: parse_date(row["valid_from"]),
          valid_to: parse_date(row["valid_to"]),
          notes: row["notes"]
        }
        if link.new_record?
          link.assign_attributes(attributes)
          link.save!
        else
          link.update_columns(
            attributes.except(:institution_source).merge(institution_source_id: source.id, updated_at: Time.current)
          )
        end
      end
    end
  end

  def resolve_authority_statuses!
    csds.find_each do |geography|
      authority_links = geography.institution_geographies.where(role: AUTHORITY_ROLES)
      if authority_links.exists?
        verified = authority_links.where(match_method: %w[
          authoritative_crosswalk source_assertion exact_identifier
        ]).exists?
        set_authority_status!(geography, verified ? "verified" : "provisional")
        next
      end

      if indigenous_authority_geography?(geography)
        set_authority_status!(geography, "unresolved")
        next
      end

      add_jurisdictional_fallback!(geography)
      set_authority_status!(geography, "provisional")
    end
  end

  def add_jurisdictional_fallback!(geography)
    namespace = PROVINCE_NAMESPACES.fetch(geography.province_code)
    institution = @release.institutions.find_by!(canonical_id: "ca/#{namespace}")
    @release.institution_geographies.create!(
      institution: institution,
      institution_geography_snapshot: geography,
      role: "administers",
      match_method: "jurisdictional_fallback",
      confidence: 0.25,
      notes: "Provisional ultimate-jurisdiction fallback; direct local governing authority remains to be reconciled"
    )
  end

  def indigenous_authority_geography?(geography)
    ON_RESERVE_TYPES.include?(geography.classification_type) ||
      INDIGENOUS_AUTHORITY_TYPES.fetch(geography.province_code, []).include?(geography.classification_type)
  end

  def set_authority_status!(geography, status)
    # Authority resolution is the final phase of the same atomic build; bypass append-only callbacks before commit.
    geography.update_columns(authority_status: status, updated_at: Time.current)
  end

  def import_coverage!(source)
    counts = csds.group(:authority_status).count
    unresolved = counts.fetch("unresolved", 0)
    rows = [
      [ "csd-inventory", "complete", "All #{expected_count} Statistics Canada SGC #{@release.geography_vintage} CSDs are frozen in this release." ],
      [ "csd-authority-mapping", unresolved.zero? ? "complete" : "partial",
        "Authority status: #{counts.sort.map { |status, count| "#{status}=#{count}" }.join(', ')}. Provisional links use exact-name reconciliation or an explicit jurisdictional fallback; unresolved CSDs have no asserted authority." ]
    ]
    rows.each do |subject, status, notes|
      @release.institution_coverages.create!(
        institution_source: source,
        scope_id: "ca/geography/csd-#{@release.geography_vintage}",
        subject: subject,
        status: status,
        notes: notes,
        source_url: source.url
      )
    end
  end

  def validate_complete_inventory!
    raise ImportError, "release does not contain all #{expected_count} CSDs" unless csds.count == expected_count
    invalid = csds.where(authority_status: %w[legacy not_applicable]).count
    raise ImportError, "#{invalid} CSDs lack an authority status" if invalid.positive?
    linked_ids = @release.institution_geographies.where(role: AUTHORITY_ROLES)
      .select(:institution_geography_snapshot_id)
    missing_links = csds.where(authority_status: %w[verified provisional]).where.not(id: linked_ids).count
    raise ImportError, "#{missing_links} resolved CSDs lack authority links" if missing_links.positive?
  end

  def csds
    @release.institution_geography_snapshots.where(
      boundary_type: "csd", census_year: @release.geography_vintage
    )
  end

  def expected_count
    @release.geography_vintage == 2021 ? EXPECTED_2021_CSD_COUNT : raise(ImportError, "unsupported CSD vintage")
  end

  def parse_date(value)
    value.present? ? Date.iso8601(value) : nil
  end
end
