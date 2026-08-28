require "digest"
require "json"

class Warehouse::InstitutionRelease::NovaScotiaMunicipalityImporter
  class ImportError < StandardError; end

  attr_reader :release

  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")

  def initialize(path:, version: nil, effective_on: nil, asset_root: DEFAULT_ASSET_ROOT, verify_assets: true)
    @path = Pathname(path)
    @requested_version = version
    @requested_effective_on = effective_on
    @asset_root = Pathname(asset_root).expand_path
    @verify_assets = verify_assets
  end

  def import!
    payload = load_payload!
    validate_release_metadata!(payload)
    validate_rows!(payload.fetch("municipalities"))

    Warehouse::Record.transaction do
      @release = create_release!(payload)
      sources = create_release_sources!(payload)
      import_province!(payload, sources) if include_jurisdiction_institution?(payload)
      payload.fetch("municipalities").each do |row|
        import_municipality!(row, payload, sources)
      end
      import_relationships!(payload, sources.fetch(:roster))
      import_coverage!(payload, sources.fetch(:roster))
      validate_previous_release!
      release.validate_complete!
    end

    release
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    raise ImportError, error.message
  end

  private

  def load_payload!
    payload = JSON.parse(@path.read)
    raise ImportError, "release manifest must be a JSON object" unless payload.is_a?(Hash)
    raise ImportError, "release manifest must contain municipalities" unless payload["municipalities"].is_a?(Array)

    payload
  rescue Errno::ENOENT, JSON::ParserError => error
    raise ImportError, "could not read release manifest: #{error.message}"
  end

  def validate_release_metadata!(payload)
    version = payload.fetch("release_version")
    effective_on = Date.iso8601(payload.fetch("effective_on"))
    published_at = Time.iso8601(payload.fetch("published_at"))
    Date.iso8601(version)

    if @requested_version.present? && @requested_version != version
      raise ImportError, "requested version #{@requested_version} does not match manifest #{version}"
    end
    if @requested_effective_on.present? && @requested_effective_on.to_date != effective_on
      raise ImportError, "requested effective date #{@requested_effective_on} does not match manifest #{effective_on}"
    end
    raise ImportError, "release version and effective date must match" unless version == effective_on.iso8601
    raise ImportError, "schema_version is required" if payload["schema_version"].blank?
    raise ImportError, "geography_vintage is required" if payload["geography_vintage"].blank?
    raise ImportError, "attribution is required" if payload["attribution"].blank?
    raise ImportError, "release #{version} already exists" if Warehouse::InstitutionRelease.exists?(version: version)

    published_at
  rescue KeyError, Date::Error, ArgumentError => error
    raise ImportError, "invalid release metadata: #{error.message}"
  end

  def validate_rows!(rows)
    raise ImportError, "municipality input must be non-empty" if rows.empty?

    canonical_ids = rows.map { |row| row["canonical_id"] }
    duplicates = canonical_ids.tally.select { |_canonical_id, count| count > 1 }.keys
    raise ImportError, "canonical IDs must be unique: #{duplicates.join(', ')}" if duplicates.any?

    invalid = rows.filter_map do |row|
      canonical_id = row["canonical_id"]
      canonical_id if canonical_id.blank? || !valid_jurisdiction_id?(canonical_id) ||
        [ row["official_name"], row["official_name_en"], row["official_name_fr"] ].all?(&:blank?)
    end
    raise ImportError, "every institution requires a jurisdiction ID and name: #{invalid.join(', ')}" if invalid.any?
  end

  def valid_jurisdiction_id?(canonical_id)
    code = province_metadata.fetch("code")
    canonical_id.start_with?("ca/#{code}/")
  end

  def create_release!(payload)
    Warehouse::InstitutionRelease.create!(
      version: payload.fetch("release_version"),
      effective_on: Date.iso8601(payload.fetch("effective_on")),
      schema_version: payload.fetch("schema_version"),
      published_at: Time.iso8601(payload.fetch("published_at")),
      geography_vintage: Integer(payload.fetch("geography_vintage")),
      attribution: payload.fetch("attribution")
    )
  end

  def create_release_sources!(payload)
    province = province_metadata(payload)
    code = province.fetch("code")
    retrieved_at = Time.iso8601(payload.fetch("source_retrieved_at"))
    {
      roster: create_source!(
        canonical_id: "ca/sources/#{code}/institution-roster/#{payload.fetch('release_version')}",
        publisher_name: payload["roster_source_publisher"].presence || province.fetch("government_name_en"),
        title_en: payload["roster_source_title"].presence || "Official municipality roster",
        url: payload.fetch("roster_source_url"),
        retrieved_at: retrieved_at,
        license: province["source_license"],
        languages: province.fetch("source_languages", [ "en" ])
      ),
      geography: create_source!(
        canonical_id: "ca/sources/statcan/sgc-2021-classification-structure",
        publisher_name: "Statistics Canada",
        title_en: "Standard Geographical Classification 2021 - Classification structure",
        url: payload.fetch("geography_source_url"),
        retrieved_at: release.published_at,
        license: "Statistics Canada Open Licence",
        languages: [ "en", "fr" ]
      ),
      province: create_source!(
        canonical_id: "ca/sources/#{code}/government-website",
        publisher_name: province.fetch("government_name_en"),
        title_en: province.fetch("government_name_en"),
        title_fr: province["government_name_fr"],
        url: province.fetch("website_url"),
        retrieved_at: retrieved_at,
        languages: province.fetch("source_languages", [ "en" ])
      )
    }
  rescue KeyError, ArgumentError => error
    raise ImportError, "invalid source metadata: #{error.message}"
  end

  def import_province!(payload, sources)
    province = province_metadata(payload)
    institution = create_institution!(
      canonical_id: "ca/#{province.fetch('code')}",
      source: sources.fetch(:province),
      name_en: province.fetch("government_name_en"),
      name_fr: province["government_name_fr"],
      website_url: province.fetch("website_url"),
      government_level: "provincial"
    )
    geography = create_geography_snapshot!(
      uid: province.fetch("statcan_code"),
      name: province.fetch("name_en"),
      boundary_type: "pr",
      vintage: payload.fetch("geography_vintage")
    )
    create_geography_link!(
      institution:, geography:, source: sources.fetch(:geography),
      match_method: "exact_identifier", confidence: 1.0,
      notes: "Province or territory Statistics Canada identifier"
    )
  end

  def import_municipality!(row, payload, sources)
    province = province_metadata(payload)
    source_path = row.fetch("canonical_id").split("/").drop(2).join("/")
    name_en, name_fr = institution_names(row, province)
    display_name = name_en.presence || name_fr
    website_url = row["website_url"].presence
    website_source_url = row["website_source_url"].presence || website_url || sources.fetch(:roster).url
    website_source = create_source!(
      canonical_id: "ca/sources/#{province.fetch('code')}/institutions/#{source_path}/profile",
      publisher_name: website_url ? display_name : sources.fetch(:roster).publisher_name,
      title_en: website_url ? "Official institution website" : "Official institution directory entry",
      url: website_source_url,
      retrieved_at: Time.iso8601(payload.fetch("source_retrieved_at")),
      languages: row.fetch("source_languages", [ ("en" if name_en), ("fr" if name_fr) ].compact)
    )
    institution = create_institution!(
      canonical_id: row.fetch("canonical_id"),
      source: website_source,
      name_en: name_en,
      name_fr: name_fr,
      website_url: website_url,
      institution_type: row.fetch("institution_type", "government"),
      legal_form: row["municipality_type"],
      contact: row["contact"],
      government_level: row.fetch("government_level", "municipal"),
      status: row.fetch("status", "active"),
      active_from: parse_date(row["active_from"]),
      active_to: parse_date(row["active_to"]),
      description_en: row["description_en"],
      description_fr: row["description_fr"]
    )

    import_identifiers!(institution, row, sources)
    import_geographies!(institution, row, payload, sources.fetch(:geography))
    import_documents!(institution, row, website_source)
  end

  def create_institution!(canonical_id:, source:, name_en:, website_url:, government_level:,
    institution_type: "government",
    name_fr: nil, legal_form: nil, contact: nil, status: "active", active_from: nil, active_to: nil,
    description_en: nil, description_fr: nil)
    Warehouse::Institution.create!(
      institution_release: release,
      institution_source: source,
      canonical_id: canonical_id,
      name_en: name_en,
      name_fr: name_fr,
      website_url: website_url,
      institution_type: institution_type,
      legal_form: legal_form,
      government_level: government_level,
      status: status,
      contact_email: contact&.dig("email"),
      contact_phone: contact&.dig("phone"),
      civic_address: contact&.dig("civic_address"),
      mailing_address: contact&.dig("mailing_address"),
      active_from: active_from,
      active_to: active_to,
      description_en: description_en,
      description_fr: description_fr
    )
  end

  def import_identifiers!(institution, row, sources)
    Array(row["identifiers"]).uniq { |identifier| [ identifier["scheme"], identifier["value"] ] }.each do |identifier|
      next if identifier["scheme"].blank? || identifier["value"].blank?

      source = identifier["scheme"].start_with?("statcan.") ? sources.fetch(:geography) : sources.fetch(:roster)
      Warehouse::InstitutionIdentifier.create!(
        institution_release: release,
        institution: institution,
        institution_source: source,
        scheme: identifier.fetch("scheme"),
        value: identifier.fetch("value").to_s,
        preferred: identifier.fetch("preferred", false)
      )
    end
  end

  def import_geographies!(institution, row, payload, source)
    Array(row["statcan_geographies"]).each do |geography_row|
      boundary_type = geography_row.fetch("boundary_type", "csd")
      source_match_method = geography_row.fetch("match_method", "exact_name")
      match_method = normalize_geography_match_method(source_match_method)
      notes = geography_row["notes"] || "Jurisdiction adapter mapping; see release coverage"
      if source_match_method != match_method
        notes = "#{notes}; source match method: #{source_match_method}"
      end
      geography = create_geography_snapshot!(
        uid: geography_row.fetch("uid").to_s,
        name: geography_row.fetch("name"),
        boundary_type: boundary_type,
        vintage: geography_row.fetch("vintage", payload.fetch("geography_vintage")),
        province_code: geography_row["province_code"]
      )
      create_geography_link!(
        institution: institution,
        geography: geography,
        source: source,
        role: geography_row.fetch("role", "governs"),
        match_method: match_method,
        confidence: geography_row.fetch("confidence", 0.8),
        valid_from: parse_date(geography_row["valid_from"]),
        valid_to: parse_date(geography_row["valid_to"]),
        notes: notes
      )
    end
  end

  def normalize_geography_match_method(value)
    aliases = {
      "exact_unique_normalized_name" => "exact_name",
      "exact_name_and_legal_type" => "exact_name",
      "manual_current_government_to_2021_csd" => "source_assertion",
      "curated_authoritative_name_or_rename" => "source_assertion",
      "official_2020_rename_to_2021_sgc_legacy_name" => "source_assertion"
    }
    normalized = aliases.fetch(value, value)
    return normalized if Warehouse::InstitutionGeography::MATCH_METHODS.include?(normalized)

    raise ImportError, "unsupported geography match method: #{value}"
  end

  def create_geography_snapshot!(uid:, name:, boundary_type:, vintage:, province_code: nil)
    vintage = Integer(vintage)
    canonical_id = Warehouse::InstitutionGeographySnapshot.canonical_id_for(
      boundary_type: boundary_type,
      census_year: vintage,
      geo_uid: uid
    )
    existing = release.institution_geography_snapshots.find_by(canonical_id: canonical_id)
    return existing if existing

    boundary = Warehouse::GeoBoundary.find_by(
      boundary_type: boundary_type,
      geo_uid: uid,
      census_year: vintage
    )
    Warehouse::InstitutionGeographySnapshot.create!(
      institution_release: release,
      canonical_id: canonical_id,
      code_system: "#{boundary_type}_#{vintage}",
      geo_uid: uid,
      boundary_type: boundary_type,
      name_en: boundary&.name_en.presence || name,
      name_fr: boundary&.name_fr,
      province_code: boundary&.province_code.presence || province_code || province_metadata["statcan_code"],
      census_year: vintage,
      authority_status: boundary_type == "pr" ? "not_applicable" : "legacy",
      geometry: boundary&.geometry,
      population: boundary&.population,
      area_sq_km: boundary&.area_sq_km
    )
  end

  def create_geography_link!(institution:, geography:, source:, role: "governs", match_method: "legacy",
    confidence: nil, valid_from: nil, valid_to: nil, notes: nil)
    Warehouse::InstitutionGeography.create!(
      institution_release: release,
      institution: institution,
      institution_geography_snapshot: geography,
      institution_source: source,
      role: role,
      match_method: match_method,
      confidence: confidence,
      valid_from: valid_from,
      valid_to: valid_to,
      notes: notes
    )
  end

  def import_relationships!(payload, source)
    Array(payload["relationships"]).each do |row|
      source_institution = release.institutions.find_by!(canonical_id: row.fetch("source_id"))
      target_institution = release.institutions.find_by!(canonical_id: row.fetch("target_id"))
      Warehouse::InstitutionRelationship.create!(
        institution_release: release,
        source_institution: source_institution,
        target_institution: target_institution,
        institution_source: source,
        relationship_type: row.fetch("relationship_type"),
        primary: row.fetch("primary", false),
        ownership_percentage: row["ownership_percentage"],
        ownership_basis: row["ownership_basis"],
        valid_from: parse_date(row["valid_from"]),
        valid_to: parse_date(row["valid_to"]),
        notes: row["notes"]
      )
    end
  end

  def import_coverage!(payload, source)
    rows = Array(payload["coverage"])
    if rows.empty?
      gaps = Array(payload["scrape_gaps"]) + Array(payload["gaps"])
      rows = [ {
        "scope_id" => "ca/#{province_metadata.fetch('code')}", "subject" => "institutions",
        "status" => "partial", "notes" => gaps.join(" | ")
      } ] if gaps.any?
    end
    rows.each do |row|
      Warehouse::InstitutionCoverage.create!(
        institution_release: release, institution_source: source,
        scope_id: row.fetch("scope_id"), subject: row.fetch("subject"),
        status: row.fetch("status"), notes: row.fetch("notes"),
        source_url: row["source_url"]
      )
    end
  end

  def import_documents!(institution, row, source)
    Array(row["documents"]).each do |document_row|
      document_source = create_document_source(institution, document_row, source)
      document = Warehouse::InstitutionDocument.create!(
        institution_release: release,
        institution: institution,
        institution_source: document_source,
        canonical_id: document_row.fetch("canonical_id"),
        document_type: document_row.fetch("document_type"),
        document_variant: document_row.fetch("document_variant"),
        title_en: document_row["title"],
        title_fr: document_row["title_fr"],
        fiscal_period_start: parse_date(document_row["fiscal_period_start"]),
        fiscal_period_end: parse_date(document_row["fiscal_period_end"]),
        published_on: parse_date(document_row["published_on"]),
        source_page_url: document_row["source_page_url"],
        download_url: document_row["download_url"],
        notes: document_row["notes"]
      )

      Array(document_row["assets"]).each do |asset_row|
        validate_asset_file!(document.canonical_id, asset_row) if @verify_assets
        Warehouse::InstitutionDocumentAsset.create!(
          institution_release: release,
          institution_document: document,
          content_sha256: asset_row.fetch("content_sha256"),
          asset_role: normalize_asset_role(asset_row),
          part_index: asset_row["part_index"],
          part_count: asset_row["part_count"],
          preferred: asset_row.fetch("preferred", false),
          download_url: asset_row.fetch("download_url"),
          retrieved_at: Time.iso8601(asset_row.fetch("retrieved_at")),
          archive_path: asset_row.fetch("archive_path"),
          mime_type: asset_row.fetch("mime_type"),
          byte_size: Integer(asset_row.fetch("byte_size")),
          rights_status: asset_row.fetch("rights_status", "metadata_only"),
          page_locator: asset_row["page_locator"]
        )
      end
    end
  end

  def create_document_source(institution, document_row, fallback_source)
    url = document_row["source_page_url"].presence || document_row["download_url"].presence
    return fallback_source unless url

    retrieved_at = Array(document_row["assets"]).filter_map { |asset| asset["retrieved_at"] }.min
    languages = Array(document_row["source_languages"]).presence ||
      Array(document_row["assets"]).flat_map { |asset| Array(asset["languages"]) }.uniq.presence ||
      (document_row["title_fr"].present? ? [ "en", "fr" ] : [ "en" ])
    create_source!(
      canonical_id: "ca/sources/reports/#{Digest::SHA256.hexdigest(document_row.fetch('canonical_id'))[0, 24]}",
      publisher_name: institution.name_en.presence || institution.name_fr,
      title_en: document_row["title"].present? ? "Source for #{document_row['title']}" : nil,
      title_fr: document_row["title_fr"].present? ? "Source pour #{document_row['title_fr']}" : nil,
      url: url,
      retrieved_at: retrieved_at ? Time.iso8601(retrieved_at) : release.published_at,
      languages: languages
    )
  end

  def create_source!(attributes)
    existing = release.institution_sources.find_by(canonical_id: attributes.fetch(:canonical_id))
    if existing
      comparable = attributes.slice(
        :publisher_name, :title_en, :title_fr, :url, :retrieved_at, :license, :attribution, :languages
      ).compact
      mismatches = comparable.filter_map do |key, expected|
        key unless existing.public_send(key) == expected
      end
      raise ImportError, "source #{existing.canonical_id} changed within one release: #{mismatches.join(', ')}" if mismatches.any?

      return existing
    end

    Warehouse::InstitutionSource.create!(attributes.merge(institution_release: release))
  end

  def validate_asset_file!(document_id, asset)
    candidate = @asset_root.join(asset.fetch("archive_path")).expand_path
    root_prefix = "#{@asset_root.to_s.delete_suffix(File::SEPARATOR)}#{File::SEPARATOR}"
    raise ImportError, "archive escapes asset root: #{candidate}" unless candidate.to_s.start_with?(root_prefix)
    raise ImportError, "missing archive for #{document_id}: #{candidate}" unless candidate.file?
    unless Digest::SHA256.file(candidate).hexdigest == asset.fetch("content_sha256")
      raise ImportError, "archive hash mismatch for #{document_id}: #{candidate}"
    end
    unless candidate.size == Integer(asset.fetch("byte_size"))
      raise ImportError, "archive size mismatch for #{document_id}: #{candidate}"
    end
    raise ImportError, "archive MIME must be application/pdf for #{document_id}" unless asset.fetch("mime_type") == "application/pdf"
    raise ImportError, "archive is not a PDF for #{document_id}: #{candidate}" unless candidate.binread(5) == "%PDF-"
  end

  def normalize_asset_role(asset)
    return "part" if asset["part_index"].present? || asset["part_count"].present?

    asset.fetch("asset_role") == "primary" ? "final" : asset.fetch("asset_role")
  end

  def parse_date(value)
    Date.iso8601(value) if value.present?
  rescue Date::Error
    raise ImportError, "invalid ISO date: #{value}"
  end

  def province_metadata(payload = nil)
    @province_metadata ||= (payload || load_payload!)["province"] || {
      "code" => "ns",
      "statcan_code" => "12",
      "name_en" => "Nova Scotia",
      "name_fr" => "Nouvelle-Écosse",
      "government_name_en" => "Government of Nova Scotia",
      "government_name_fr" => "Gouvernement de la Nouvelle-Écosse",
      "website_url" => "https://www.novascotia.ca/",
      "source_languages" => [ "en", "fr" ],
      "source_license" => "Open Government Licence - Nova Scotia"
    }
  end

  def include_jurisdiction_institution?(payload)
    payload.fetch("include_jurisdiction_institution", true)
  end

  def institution_names(row, province)
    name_en = row["official_name_en"].presence
    name_fr = row["official_name_fr"].presence
    unqualified = row["official_name"].presence
    if unqualified
      source_languages = row.fetch("source_languages", province.fetch("source_languages", [ "en" ]))
      source_languages == [ "fr" ] ? name_fr ||= unqualified : name_en ||= unqualified
    end
    [ name_en, name_fr ]
  end

  def validate_previous_release!
    previous = Warehouse::InstitutionRelease.where("effective_on < ?", release.effective_on).order(effective_on: :desc).first
    return unless previous

    previous_by_id = previous.institutions.index_by(&:canonical_id)
    release.institutions.each do |institution|
      prior = previous_by_id[institution.canonical_id]
      next unless prior
      next if prior.institution_type == institution.institution_type && prior.government_level == institution.government_level

      raise ImportError, "canonical institution ID changed meaning: #{institution.canonical_id}"
    end

    previous_identifiers = previous.institution_identifiers.joins(:institution).pluck(
      :scheme, :value, "warehouse.institutions.canonical_id"
    ).to_h { |scheme, value, canonical_id| [ [ scheme, value ], canonical_id ] }
    release.institution_identifiers.includes(:institution).each do |identifier|
      prior_id = previous_identifiers[[ identifier.scheme, identifier.value ]]
      next if prior_id.nil? || prior_id == identifier.institution.canonical_id

      raise ImportError,
        "identifier #{identifier.scheme}=#{identifier.value} moved from #{prior_id} to #{identifier.institution.canonical_id}"
    end

    previous_documents = previous.institution_documents.includes(:institution).index_by(&:canonical_id)
    release.institution_documents.includes(:institution).each do |document|
      prior = previous_documents[document.canonical_id]
      next unless prior
      prior_meaning = [ prior.institution.canonical_id, prior.document_type, prior.document_variant, prior.fiscal_period_end ]
      current_meaning = [ document.institution.canonical_id, document.document_type, document.document_variant, document.fiscal_period_end ]
      next if prior_meaning == current_meaning

      raise ImportError, "canonical document ID changed meaning: #{document.canonical_id}"
    end

    missing = previous_by_id.keys - release.institutions.pluck(:canonical_id)
    Rails.logger.warn("Ontology release #{release.version} omits prior institutions: #{missing.join(', ')}") if missing.any?
  end
end
