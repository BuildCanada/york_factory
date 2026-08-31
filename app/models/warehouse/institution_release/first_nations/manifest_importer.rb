require "digest"
require "json"

module Warehouse::InstitutionRelease::FirstNations
  class ManifestImporter
    class ImportError < StandardError; end

    def initialize(release:, path:, asset_inventory_path: nil, asset_root: FinancialStatementArchiver::DEFAULT_ASSET_ROOT,
      verify_assets: true)
      @release = release
      @path = Pathname(path)
      @asset_inventory_path = asset_inventory_path && Pathname(asset_inventory_path)
      @asset_root = Pathname(asset_root).expand_path
      @verify_assets = verify_assets
    end

    def import!
      payload = JSON.parse(@path.read)
      validate!(payload)
      Warehouse::Record.transaction do
        sources = import_sources!(payload)
        institutions = payload.fetch("bands").to_h do |row|
          institution = import_band!(row, sources)
          [ row.fetch("band_number").to_s, institution ]
        end
        Array(payload["indigenous_governments"]).each do |row|
          import_indigenous_government!(row, sources)
        end
        import_parent_relationships!(payload, institutions, sources.fetch("isc_location"))
        import_assets!
        import_coverage!(payload, sources)
      end
      @release.institutions.where(government_level: "first_nation")
    rescue Errno::ENOENT, JSON::ParserError, KeyError, Date::Error, ActiveRecord::ActiveRecordError => error
      raise ImportError, error.message
    end

    private

    def validate!(payload)
      raise ImportError, "manifest must contain bands" unless payload["bands"].is_a?(Array) && payload["bands"].any?
      raise ImportError, "manifest release does not match target release" unless payload.fetch("release_version") == @release.version
      raise ImportError, "manifest geography vintage does not match target release" unless Integer(payload.fetch("geography_vintage")) == @release.geography_vintage

      governments = Array(payload["indigenous_governments"])
      canonical_ids = (payload.fetch("bands") + governments).map { |row| row.fetch("canonical_id") }
      band_numbers = payload.fetch("bands").map { |row| row.fetch("band_number").to_s }
      raise ImportError, "duplicate band canonical IDs" unless canonical_ids.uniq.length == canonical_ids.length
      raise ImportError, "duplicate ISC band numbers" unless band_numbers.uniq.length == band_numbers.length
      payload.fetch("bands").each do |row|
        raise ImportError, "band canonical IDs must use ca/fn" unless row.fetch("canonical_id").start_with?("ca/fn/")
        raise ImportError, "band government level must be first_nation" unless row.fetch("government_level") == "first_nation"
        Array(row["statcan_geographies"]).each do |geography|
          raise ImportError, "band CSD associations must be headquartered_in" unless geography.fetch("role") == "headquartered_in"
        end
      end
      source_keys = payload.fetch("sources").pluck("key")
      governments.each do |row|
        raise ImportError, "Indigenous government canonical IDs must use ca/fn" unless row.fetch("canonical_id").start_with?("ca/fn/")
        raise ImportError, "Indigenous government level must be first_nation" unless row.fetch("government_level") == "first_nation"
        raise ImportError, "unknown Indigenous government source" unless source_keys.include?(row.fetch("source_key"))
      end
    end

    def import_sources!(payload)
      payload.fetch("sources").to_h do |row|
        key = row.fetch("key")
        canonical_id = row["canonical_id"] || {
          "isc_location" => "ca/sources/isc/first-nations-location",
          "fnp" => "ca/sources/isc/first-nation-profiles",
          "fnfta" => "ca/sources/isc/fnfta-financial-statements",
          "statcan_csd_2021" => "ca/sources/statcan/csd-2021-cartographic-boundaries"
        }.fetch(key)
        attributes = {
          institution_release: @release, canonical_id: canonical_id,
          publisher_name: row["publisher_name"] || row.fetch("publisher"), title_en: row.fetch("title_en"),
          title_fr: row["title_fr"], url: row.fetch("url"),
          retrieved_at: Time.iso8601(row["retrieved_at"] || payload.fetch("retrieved_at")),
          license: row["license"], languages: row.fetch("languages")
        }
        existing = @release.institution_sources.find_by(canonical_id: canonical_id)
        if existing && existing.slice(:publisher_name, :url, :license, :languages) != attributes.slice(:publisher_name, :url, :license, :languages).stringify_keys
          raise ImportError, "source #{canonical_id} conflicts with an existing release source"
        end
        [ key, existing || Warehouse::InstitutionSource.create!(attributes) ]
      end
    end

    def import_band!(row, sources)
      if @release.institutions.exists?(canonical_id: row.fetch("canonical_id"))
        raise ImportError, "institution already exists: #{row.fetch('canonical_id')}"
      end
      contact = row.fetch("contact", {})
      institution = Warehouse::Institution.create!(
        institution_release: @release, institution_source: sources.fetch("fnp"),
        canonical_id: row.fetch("canonical_id"), name_en: row.fetch("name_en"), name_fr: row["name_fr"],
        website_url: row["website_url"], institution_type: "government", legal_form: "First Nation band",
        government_level: "first_nation", status: row.fetch("status", "active"),
        contact_phone: contact["phone"], civic_address: contact["civic_address"],
        mailing_address: contact["mailing_address"], fiscal_year_start_month: 4, default_currency: "CAD"
      )
      Warehouse::InstitutionIdentifier.create!(
        institution_release: @release, institution: institution,
        institution_source: sources.fetch("isc_location"), scheme: "isc.band_number",
        value: row.fetch("band_number").to_s, preferred: true
      )
      import_geographies!(row, institution, sources.fetch("statcan_csd_2021"))
      import_reports!(row, institution, sources.fetch("fnfta"))
      institution
    end

    def import_indigenous_government!(row, sources)
      if @release.institutions.exists?(canonical_id: row.fetch("canonical_id"))
        raise ImportError, "institution already exists: #{row.fetch('canonical_id')}"
      end

      contact = row.fetch("contact", {})
      Warehouse::Institution.create!(
        institution_release: @release,
        institution_source: sources.fetch(row.fetch("source_key")),
        canonical_id: row.fetch("canonical_id"),
        name_en: row.fetch("name_en"),
        name_fr: row["name_fr"],
        website_url: row["website_url"],
        institution_type: row.fetch("institution_type", "government"),
        legal_form: row.fetch("legal_form", "Indigenous self-government"),
        government_level: "first_nation",
        status: row.fetch("status", "active"),
        contact_email: contact["email"],
        contact_phone: contact["phone"],
        civic_address: contact["civic_address"],
        mailing_address: contact["mailing_address"],
        fiscal_year_start_month: row.fetch("fiscal_year_start_month", 4),
        default_currency: "CAD"
      )
    end

    def import_geographies!(row, institution, source)
      Array(row["statcan_geographies"]).each do |geography|
        uid = geography.fetch("uid").to_s
        canonical_id = Warehouse::InstitutionGeographySnapshot.canonical_id_for(
          boundary_type: "csd", census_year: 2021, geo_uid: uid
        )
        snapshot = @release.institution_geography_snapshots.find_or_create_by!(canonical_id: canonical_id) do |record|
          record.code_system = "csd_2021"
          record.geo_uid = uid
          record.boundary_type = "csd"
          record.name_en = geography.fetch("name_en")
          record.name_fr = geography["name_fr"]
          record.province_code = geography["province_code"]
          record.census_year = 2021
          record.classification_type = geography["classification_type"]
          record.population = geography["population"]
          record.area_sq_km = geography["area_sq_km"]
        end
        Warehouse::InstitutionGeography.create!(
          institution_release: @release, institution: institution,
          institution_geography_snapshot: snapshot, institution_source: source,
          role: "headquartered_in", match_method: "source_assertion", confidence: 1.0,
          notes: "ISC location associated with the First Nation profile; this is not a land-governance assertion"
        )
      end
    end

    def import_reports!(row, institution, source)
      Array(row["reports"]).each do |report|
        Warehouse::InstitutionDocument.create!(
          institution_release: @release, institution: institution, institution_source: source,
          canonical_id: report.fetch("canonical_id"), document_type: "financial-statements",
          document_variant: "consolidated", title_en: report.fetch("title_en"), title_fr: report["title_fr"],
          fiscal_period_start: Date.iso8601(report.fetch("fiscal_period_start")),
          fiscal_period_end: Date.iso8601(report.fetch("fiscal_period_end")),
          published_on: parse_date(report["date_received"]), source_page_url: report.fetch("source_page_url"),
          download_url: report.fetch("download_url"),
          notes: "FNFTA fiscal year #{report.fetch('fiscal_year_label')}; period dates inferred from the published fiscal-year label"
        )
      end
    end

    def import_assets!
      path = @asset_inventory_path || @path.dirname.join("financial-statement-assets.json")
      return unless path.exist?

      inventory = JSON.parse(path.read)
      raise ImportError, "asset inventory release does not match target release" unless inventory.fetch("release_version") == @release.version
      Array(inventory["assets"]).each do |asset|
        next if asset["error"].present?
        document = @release.institution_documents.find_by!(canonical_id: asset.fetch("document_canonical_id"))
        archive_path = asset.fetch("archive_path")
        file = @asset_root.join(archive_path)
        if @verify_assets
          raise ImportError, "archived statement missing: #{file}" unless file.file?
          raise ImportError, "archived statement checksum mismatch: #{file}" unless Digest::SHA256.file(file).hexdigest == asset.fetch("content_sha256")
        end
        Warehouse::InstitutionDocumentAsset.create!(
          institution_release: @release, institution_document: document,
          content_sha256: asset.fetch("content_sha256"), asset_role: asset.fetch("asset_role", "final"),
          preferred: asset.fetch("preferred", true), download_url: asset.fetch("download_url"),
          retrieved_at: Time.iso8601(asset.fetch("retrieved_at")), archive_path: archive_path,
          mime_type: asset.fetch("mime_type"), byte_size: Integer(asset.fetch("byte_size")),
          rights_status: asset.fetch("rights_status", "metadata_only")
        )
      end
    end

    def import_parent_relationships!(payload, institutions, source)
      payload.fetch("bands").each do |row|
        parent_number = row["parent_band_number"].presence&.to_s
        next unless parent_number && institutions[parent_number]
        next if parent_number == row.fetch("band_number").to_s

        Warehouse::InstitutionRelationship.create!(
          institution_release: @release, source_institution: institutions.fetch(row.fetch("band_number").to_s),
          target_institution: institutions.fetch(parent_number), institution_source: source,
          relationship_type: "administrative_parent", primary: true,
          notes: "ISC First Nations Location parent First Nation field"
        )
      end
    end

    def import_coverage!(payload, sources)
      bands = payload.fetch("bands")
      other_governments = Array(payload["indigenous_governments"])
      governments = bands + other_governments
      summary = payload.fetch("normalization_summary", {})
      report_bands = bands.count { |band| Array(band["reports"]).any? }
      website_governments = governments.count { |government| government["website_url"].present? }
      geography_governments = governments.count { |government| Array(government["statcan_geographies"]).any? }
      assets_path = @asset_inventory_path || @path.dirname.join("financial-statement-assets.json")
      asset_rows = assets_path.exist? ? Array(JSON.parse(assets_path.read)["assets"]) : []
      asset_successes = asset_rows.count { |asset| asset["error"].blank? }
      asset_failures = asset_rows.length - asset_successes
      rows = [
        [ "institutions", "complete", "#{bands.length} current standalone band governments and #{other_governments.length} other Indigenous governments; #{Array(payload['skipped_entities']).length} ISC parented components excluded." ],
        [ "websites", website_governments == governments.length ? "complete" : "partial", "Official website discovered for #{website_governments} of #{governments.length} Indigenous governments." ],
        [ "geographies", geography_governments == governments.length ? "complete" : "partial", "StatsCan 2021 headquarters geography linked for #{geography_governments} of #{governments.length} Indigenous governments." ],
        [ "financial-statements", report_bands == bands.length ? "complete" : "partial", "FNFTA audited-statement links found for #{report_bands} of #{bands.length} bands (#{summary['report_count'] || bands.sum { |band| Array(band['reports']).length }} documents)." ],
        [ "document-assets", asset_failures.zero? && asset_successes.positive? ? "complete" : "partial", "#{asset_successes} FNFTA assets archived; #{asset_failures} downloads failed; #{asset_rows.length} links attempted." ]
      ]
      rows.each do |subject, status, notes|
        source = %w[financial-statements document-assets].include?(subject) ? sources.fetch("fnfta") : sources.fetch(subject == "geographies" ? "statcan_csd_2021" : "isc_location")
        Warehouse::InstitutionCoverage.create!(
          institution_release: @release, institution_source: source, scope_id: "ca/fn",
          subject: subject, status: status, notes: notes, source_url: source.url
        )
      end
    end

    def parse_date(value)
      return nil if value.blank?
      Date.iso8601(value)
    rescue Date::Error
      nil
    end
  end
end
