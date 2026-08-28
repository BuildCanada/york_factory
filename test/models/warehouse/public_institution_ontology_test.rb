require "test_helper"
require "digest"
require "fileutils"
require "tmpdir"
require Rails.root.join("script/scrape_western_municipal_financial_reports")

class Warehouse::PublicInstitutionOntologyTest < ActiveSupport::TestCase
  setup do
    @release = release("2026-08-14")
    @source = source(@release)
  end

  test "release metadata is date-aligned and append-only" do
    invalid = Warehouse::InstitutionRelease.new(
      version: "2026-08-15",
      effective_on: Date.new(2026, 8, 16),
      published_at: Time.utc(2026, 8, 15),
      geography_vintage: 2021,
      attribution: "Example"
    )
    refute invalid.valid?

    @release.attribution = "Changed"
    refute @release.save
    assert_includes @release.errors[:base], "ontology releases are append-only"
  end

  test "institutions use semantic IDs and reserve source geography and document namespaces" do
    markham = institution("ca/on/markham/fire-and-emergency-services", name_en: "Markham Fire")
    assert_equal "ca/on/markham/fire-and-emergency-services", markham.canonical_id

    %w[ca/sources/example ca/geography/csd-2021/123 ca/on/markham/documents/report].each do |canonical_id|
      record = Warehouse::Institution.new(
        institution_release: @release,
        canonical_id: canonical_id,
        name_en: "Invalid",
        institution_type: "government",
        government_level: "other"
      )
      refute record.valid?, canonical_id
    end
  end

  test "sources are copied into each release and may differ without becoming stale" do
    later = release("2026-08-15")
    later_source = source(later, url: "https://example.test/directory-v2")

    assert_equal @source.canonical_id, later_source.canonical_id
    refute_equal @source.url, later_source.url
    assert_equal 2, Warehouse::InstitutionSource.where(canonical_id: @source.canonical_id).count
  end

  test "external identifiers remain unambiguous within a release" do
    markham = institution("ca/on/markham", name_en: "City of Markham")
    vaughan = institution("ca/on/vaughan", name_en: "City of Vaughan")
    Warehouse::InstitutionIdentifier.create!(
      institution_release: @release,
      institution: markham,
      scheme: "statcan.csd",
      value: "3519036",
      preferred: true
    )

    duplicate = Warehouse::InstitutionIdentifier.new(
      institution_release: @release,
      institution: vaughan,
      scheme: "statcan.csd",
      value: "3519036"
    )
    refute duplicate.valid?

    second_preferred = Warehouse::InstitutionIdentifier.new(
      institution_release: @release,
      institution: markham,
      scheme: "statcan.csd",
      value: "another",
      preferred: true
    )
    refute second_preferred.valid?
  end

  test "jurisdiction-specific match labels normalize to the shallow release vocabulary" do
    importer = Warehouse::InstitutionRelease::MunicipalityImporter.allocate

    assert_equal "exact_name",
      importer.send(:normalize_geography_match_method, "exact_name_and_legal_type")
    assert_equal "source_assertion",
      importer.send(:normalize_geography_match_method, "curated_authoritative_name_or_rename")
    assert_raises(Warehouse::InstitutionRelease::MunicipalityImporter::ImportError) do
      importer.send(:normalize_geography_match_method, "fuzzy_guess")
    end
  end

  test "composite foreign keys reject cross-release graph records" do
    markham = institution("ca/on/markham", name_en: "City of Markham")
    later = release("2026-08-15")

    assert_raises(ActiveRecord::InvalidForeignKey) do
      Warehouse::Record.transaction(requires_new: true) do
        Warehouse::InstitutionIdentifier.create!(
          institution_release: later,
          institution: markham,
          scheme: "statcan.csd",
          value: "3519036"
        )
      end
    end
  end

  test "a First Nation is a peer government associated with several frozen geographies" do
    nation = institution(
      "ca/fn/example-first-nation",
      name_en: "Example First Nation",
      government_level: "first_nation"
    )
    reserve = geography("csd", "TEST-FN-1", "Example reserve")
    service_area = geography("csd", "TEST-FN-2", "Example service area")

    [ [ reserve, "governs" ], [ service_area, "serves" ], [ reserve, "headquartered_in" ] ].each do |area, role|
      Warehouse::InstitutionGeography.create!(
        institution_release: @release,
        institution: nation,
        institution_geography_snapshot: area,
        institution_source: @source,
        role: role
      )
    end

    assert_equal 3, nation.institution_geographies.count
    assert_equal "ca/geography/csd-2021/test-fn-1", reserve.canonical_id
  end

  test "joint and partial ownership uses multiple typed edges without requiring a 100 percent total" do
    company = institution("ca/joint/example-utility", name_en: "Example Utility", government_level: "joint")
    owner_a = institution("ca/on/markham", name_en: "City of Markham")
    owner_b = institution("ca/on/vaughan", name_en: "City of Vaughan")

    [ [ owner_a, 40 ], [ owner_b, 35 ] ].each do |owner, percentage|
      Warehouse::InstitutionRelationship.create!(
        institution_release: @release,
        source_institution: company,
        target_institution: owner,
        institution_source: @source,
        relationship_type: "owned_by",
        ownership_basis: "equity",
        ownership_percentage: percentage
      )
    end

    assert_equal 2, company.outgoing_relationships.count
  end

  test "complete release validation rejects a primary parent cycle" do
    a = institution("ca/on/a", name_en: "A")
    b = institution("ca/on/b", name_en: "B")
    Warehouse::InstitutionRelationship.create!(
      institution_release: @release,
      source_institution: a,
      target_institution: b,
      relationship_type: "administrative_parent",
      primary: true
    )
    Warehouse::InstitutionRelationship.create!(
      institution_release: @release,
      source_institution: b,
      target_institution: a,
      relationship_type: "administrative_parent",
      primary: true
    )

    assert_raises(ActiveRecord::RecordInvalid) { @release.validate_complete! }
  end

  test "document works have semantic IDs while drafts finals and parts are assets" do
    town = institution("ca/ns/amherst", name_en: "Town of Amherst")
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release,
      institution: town,
      institution_source: @source,
      canonical_id: "ca/ns/amherst/documents/financial-statements/2025/consolidated",
      document_type: "financial-statements",
      document_variant: "consolidated",
      fiscal_period_end: Date.new(2025, 3, 31),
      source_page_url: "https://example.test/amherst/finance"
    )

    Dir.mktmpdir do |directory|
      first = create_pdf_asset(directory, "draft")
      second = create_pdf_asset(directory, "final")
      create_asset(document, first, role: "draft")
      create_asset(document, second, role: "final", preferred: true)
    end

    assert_equal 1, town.institution_documents.count
    assert_equal 2, document.institution_document_assets.count
    assert_equal "final", document.institution_document_assets.find_by!(preferred: true).asset_role
  end

  test "release manifest builder is deterministic and preserves per-batch audit records" do
    Dir.mktmpdir do |directory|
      base_path, batch_a, batch_b = write_builder_inputs(directory)
      output_a = File.join(directory, "release-a.json")
      output_b = File.join(directory, "release-b.json")

      build_manifest(base_path, [ batch_a, batch_b ], output_a)
      build_manifest(base_path, [ batch_a, batch_b ], output_b)

      assert_equal File.binread(output_a), File.binread(output_b)
      payload = JSON.parse(File.read(output_a))
      town = payload.fetch("municipalities").first
      assert_equal 2, town.fetch("documents").length
      financial_statements = town.fetch("documents").find do |document|
        document["document_type"] == "financial-statements"
      end
      assert_equal 2, financial_statements.fetch("assets").length
      assert_equal 2, payload.dig("scrape_audit", "municipalities", "ca/ns/example-town").length
      assert_equal "ca/ns/example-town/documents/financial-statements/2025/consolidated",
        financial_statements.fetch("canonical_id")
    end
  end

  test "manifest builder refuses release recuts" do
    Dir.mktmpdir do |directory|
      base_path, batch_a, = write_builder_inputs(directory)
      output = File.join(directory, "release.json")
      build_manifest(base_path, [ batch_a ], output)

      assert_raises(Warehouse::InstitutionRelease::NovaScotiaMunicipalityManifestBuilder::BuildError) do
        build_manifest(base_path, [ batch_a ], output)
      end
    end
  end

  test "manifest builder rejects duplicate canonical IDs instead of overwriting a jurisdiction" do
    Dir.mktmpdir do |directory|
      base_path, batch_a, = write_builder_inputs(directory)
      base = JSON.parse(File.read(base_path))
      base.fetch("municipalities") << base.fetch("municipalities").first.dup
      File.write(base_path, JSON.pretty_generate(base))

      error = assert_raises(Warehouse::InstitutionRelease::NovaScotiaMunicipalityManifestBuilder::BuildError) do
        build_manifest(base_path, [ batch_a ], File.join(directory, "release.json"))
      end
      assert_includes error.message, "duplicate canonical IDs"
    end
  end

  test "importer requires exact release metadata and creates frozen sources geographies works and assets" do
    Dir.mktmpdir do |directory|
      asset = create_pdf_asset(directory, "statement")
      manifest = importer_manifest(asset)
      manifest.fetch(:municipalities).first[:official_name_fr] = "Ville Exemple"
      manifest.fetch(:municipalities).first.fetch(:documents).first.fetch(:assets).first[:asset_role] = "primary"
      manifest_path = File.join(directory, "manifest.json")
      File.write(manifest_path, JSON.pretty_generate(manifest))

      mismatch = Warehouse::InstitutionRelease::NovaScotiaMunicipalityImporter.new(
        path: manifest_path,
        version: "2026-08-17",
        asset_root: directory
      )
      assert_raises(Warehouse::InstitutionRelease::NovaScotiaMunicipalityImporter::ImportError) { mismatch.import! }

      imported = Warehouse::InstitutionRelease::NovaScotiaMunicipalityImporter.new(
        path: manifest_path,
        version: "2026-08-16",
        asset_root: directory
      ).import!
      town = imported.institutions.find_by!(canonical_id: "ca/ns/example-town")
      assert_equal "Town of Example", town.name_en
      assert_equal "Ville Exemple", town.name_fr
      assert_equal 2, imported.institutions.count
      assert_equal 1, town.institution_documents.count
      assert_equal 1, town.institution_documents.first.institution_document_assets.count
      assert_equal "final", town.institution_documents.first.institution_document_assets.first.asset_role
      assert_equal "https://example.test/town/finance", town.institution_documents.first.institution_source.url
      assert_equal "ca/geography/csd-2021/1299999",
        town.institution_geographies.first.institution_geography_snapshot.canonical_id
    end
  end

  test "importer preserves proposed institutions and future activation dates" do
    Dir.mktmpdir do |directory|
      asset = create_pdf_asset(directory, "statement")
      manifest = importer_manifest(asset)
      town = manifest.fetch(:municipalities).first
      town[:status] = "proposed"
      town[:active_from] = "2026-11-06"
      town[:description_en] = "Incorporation takes effect after this release."
      path = File.join(directory, "manifest.json")
      File.write(path, JSON.pretty_generate(manifest))

      imported = Warehouse::InstitutionRelease::MunicipalityImporter.new(
        path: path, asset_root: directory
      ).import!
      institution = imported.institutions.find_by!(canonical_id: "ca/ns/example-town")
      assert_equal "proposed", institution.status
      assert_equal Date.new(2026, 11, 6), institution.active_from
      refute institution.active_at?
    end
  end

  test "combined importer creates one release from multiple provincial manifests" do
    Dir.mktmpdir do |directory|
      asset = create_pdf_asset(directory, "shared statement")
      ns = JSON.parse(importer_manifest(asset).to_json)
      ns["province"] = province_metadata("ns", "12", "Nova Scotia")
      ab = JSON.parse(ns.to_json)
      ab["province"] = province_metadata("ab", "48", "Alberta")
      ab["roster_source_url"] = "https://example.test/ab-roster"
      town = ab.fetch("municipalities").first
      town["canonical_id"] = "ca/ab/example-town"
      town["official_name"] = "Town of Alberta Example"
      town.fetch("identifiers").first["value"] = "4899999"
      town.fetch("statcan_geographies").first["uid"] = "4899999"
      town.fetch("documents").first["canonical_id"] =
        "ca/ab/example-town/documents/financial-statements/2025/consolidated"

      paths = [ [ "ns.json", ns ], [ "ab.json", ab ] ].map do |name, payload|
        path = File.join(directory, name)
        File.write(path, JSON.pretty_generate(payload))
        path
      end
      imported = Warehouse::InstitutionRelease::CombinedMunicipalityImporter.new(
        paths: paths,
        version: "2026-08-16",
        asset_root: directory
      ).import!

      assert_equal 4, imported.institutions.count
      assert_equal 2, imported.institution_documents.count
      assert_equal %w[ca/ab ca/ns],
        imported.institutions.where(government_level: "provincial").order(:canonical_id).pluck(:canonical_id)
      assert_equal 1,
        imported.institution_sources.where(canonical_id: "ca/sources/statcan/sgc-2021-classification-structure").count
    end
  end

  test "importer preserves explicit hierarchy generic geography roles and missing official websites" do
    Dir.mktmpdir do |directory|
      asset = create_pdf_asset(directory, "statement")
      manifest = importer_manifest(asset)
      town = manifest.fetch(:municipalities).first
      town[:website_url] = nil
      town[:institution_type] = "board"
      town[:statcan_geographies] = [ {
        uid: "1201", name: "Example Region", boundary_type: "cd", role: "serves",
        province_code: "12"
      } ]
      manifest[:relationships] = [ {
        source_id: "ca/ns/example-town", target_id: "ca/ns",
        relationship_type: "controlled_by", ownership_basis: "statutory"
      } ]
      manifest[:coverage] = [ {
        scope_id: "ca/ns", subject: "financial-statements", status: "partial",
        notes: "Official statements were found for a subset of institutions.",
        source_url: "https://example.test/finance"
      } ]
      path = File.join(directory, "manifest.json")
      File.write(path, JSON.pretty_generate(manifest))

      imported = Warehouse::InstitutionRelease::MunicipalityImporter.new(
        path: path, asset_root: directory
      ).import!
      town = imported.institutions.find_by!(canonical_id: "ca/ns/example-town")

      assert_nil town.website_url
      assert_equal "board", town.institution_type
      assert_equal "controlled_by", town.outgoing_relationships.sole.relationship_type
      geography_link = town.institution_geographies.sole
      assert_equal "serves", geography_link.role
      assert_equal "cd", geography_link.institution_geography_snapshot.boundary_type
      assert_equal "partial", imported.institution_coverages.sole.status
    end
  end

  test "financial returns and statements of financial information remain distinct document works" do
    town = institution("ca/bc/example", name_en: "Example")

    %w[financial-data-return statement-of-financial-information].each do |type|
      document = Warehouse::InstitutionDocument.new(
        institution_release: @release,
        institution: town,
        institution_source: @source,
        canonical_id: "ca/bc/example/documents/#{type}/2025/general",
        document_type: type,
        document_variant: "general"
      )
      assert_predicate document, :valid?
    end
  end

  test "western source adapter keeps Kananaskis and SOFI semantics distinct" do
    Dir.mktmpdir do |directory|
      scraper = WesternMunicipalFinancialReportScraper.new(
        province: "bc", output_dir: directory, retrieved_at: "2026-08-21T00:00:00Z",
        asset_root: directory, statcan_structure: File.join(directory, "unused.csv")
      )
      scraper.define_singleton_method(:archive_pdf) do |_url|
        { "content_sha256" => "a" * 64, "archive_path" => "sha256/aa/#{'a' * 64}.pdf" }
      end

      assert_equal "kananaskis-improvement-district", scraper.send(
        :institution_slug, "Kananaskis Improvement District", "Improvement District"
      )
      sofi = scraper.send(
        :classify_and_archive_bc_report,
        { "canonical_id" => "ca/bc/example", "official_name" => "Example" },
        { label: "2025 Statement of Financial Information", url: "https://example.test/2025-sofi.pdf",
          source_page_url: "https://example.test/finance" }
      )
      annual = scraper.send(
        :classify_and_archive_bc_report,
        { "canonical_id" => "ca/bc/example", "official_name" => "Example" },
        { label: "2026 Annual Report", url: "https://example.test/2026-annual-report.pdf",
          source_page_url: "https://example.test/reports" }
      )

      assert_equal "statement-of-financial-information", sofi.fetch("document_type")
      assert_equal "2025-12-31", sofi.fetch("fiscal_period_end")
      assert_equal "annual-report", annual.fetch("document_type")
      refute annual.key?("fiscal_period_end")
    end
  end

  test "export contract contains release-scoped parquet tables including explicit coverage" do
    exporter = Warehouse::InstitutionRelease::Exporter.new(
      @release,
      output_directory: File.join(Dir.tmpdir, "unused-ontology-export"),
      verify_assets: false
    )
    queries = exporter.send(:export_queries)
    loader = exporter.send(:load_sql)

    assert_equal %w[
      coverage.parquet document_assets.parquet documents.parquet
      financial_statement_extractions.parquet financial_statement_facts.parquet geographies.parquet identifiers.parquet
      institution_geographies.parquet institutions.parquet relationships.parquet
      releases.parquet sources.parquet
    ], queries.keys.sort
    assert_includes queries.fetch("document_assets.parquet"), "a.rights_status = 'redistributable'"
    assert_includes queries.fetch("sources.parquet"), "release_version"
    assert_includes queries.fetch("coverage.parquet"), "c.status"
    assert_includes loader, "BEGIN TRANSACTION;"
    assert_includes loader, "document_assets.parquet"
    assert_includes loader, "coverage.parquet"
    assert_includes loader, "financial_statement_facts.parquet"
    refute_includes loader, "DELETE FROM"
  end

  test "release asset validation accepts source-published DOCX and checks its package type" do
    exporter = Warehouse::InstitutionRelease::Exporter.new(
      @release,
      output_directory: File.join(Dir.tmpdir, "unused-ontology-export")
    )
    asset = Struct.new(:mime_type).new(
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )

    Dir.mktmpdir do |directory|
      path = Pathname(directory).join("statement.docx")
      path.binwrite("PK\x03\x04word/document.xml".b)
      assert_nothing_raised { exporter.send(:validate_asset_content!, asset, path) }

      asset.mime_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      assert_raises(Warehouse::InstitutionRelease::Exporter::ExportError) do
        exporter.send(:validate_asset_content!, asset, path)
      end
    end
  end

  test "complete CSD inventory distinguishes verified governance provisional administration and unresolved land" do
    province = institution("ca/ns", name_en: "Government of Nova Scotia", government_level: "provincial")
    town = institution("ca/ns/example-town", name_en: "Town of Example")
    existing = geography("csd", "1200001", "Example")
    Warehouse::InstitutionGeography.create!(
      institution_release: @release,
      institution: town,
      institution_geography_snapshot: existing,
      institution_source: @source,
      role: "governs",
      match_method: "exact_name",
      confidence: 0.8
    )

    Dir.mktmpdir do |directory|
      inventory_path = File.join(directory, "inventory.json")
      File.write(inventory_path, JSON.generate(
        release_version: @release.version,
        geography_vintage: 2021,
        retrieved_at: @release.published_at.iso8601,
        expected_csd_count: 4,
        source: {
          canonical_id: @source.canonical_id,
          publisher_name: @source.publisher_name,
          title_en: @source.title_en,
          url: @source.url,
          languages: [ "en" ]
        },
        csds: [
          csd_inventory_row("1200001", "Example", "T"),
          csd_inventory_row("1200002", "Unorganized Example", "NO"),
          csd_inventory_row("1200003", "Example Reserve", "IRI"),
          csd_inventory_row("6000004", "Example Self-government", "SG", province_code: "60")
        ]
      ))
      importer = Warehouse::InstitutionRelease::CsdAuthorityImporter.new(
        release: @release,
        inventory_path: inventory_path
      )
      importer.define_singleton_method(:expected_count) { 4 }
      importer.import!

      assert_equal "provisional", existing.reload.authority_status
      unorganized = @release.institution_geography_snapshots.find_by!(geo_uid: "1200002")
      assert_equal "provisional", unorganized.authority_status
      fallback = unorganized.institution_geographies.find_by!(role: "administers")
      assert_equal province, fallback.institution
      assert_equal "jurisdictional_fallback", fallback.match_method
      reserve = @release.institution_geography_snapshots.find_by!(geo_uid: "1200003")
      assert_equal "unresolved", reserve.authority_status
      self_government = @release.institution_geography_snapshots.find_by!(geo_uid: "6000004")
      assert_equal "unresolved", self_government.authority_status
      coverage = @release.institution_coverages.find_by!(subject: "csd-authority-mapping")
      assert_equal "partial", coverage.status
      assert_includes coverage.notes, "unresolved=2"
    end
  end

  private

  def release(version)
    Warehouse::InstitutionRelease.create!(
      version: version,
      effective_on: Date.iso8601(version),
      schema_version: "1.0",
      published_at: Time.iso8601("#{version}T00:00:00Z"),
      geography_vintage: 2021,
      attribution: "Example attribution"
    )
  end

  def source(release, url: "https://example.test/government-directory")
    Warehouse::InstitutionSource.create!(
      institution_release: release,
      canonical_id: "ca/sources/example-government-directory",
      publisher_name: "Example government",
      title_en: "Government directory",
      url: url,
      retrieved_at: release.published_at,
      languages: [ "en" ]
    )
  end

  def institution(canonical_id, name_en:, government_level: "municipal")
    Warehouse::Institution.create!(
      institution_release: @release,
      institution_source: @source,
      canonical_id: canonical_id,
      name_en: name_en,
      institution_type: "government",
      government_level: government_level,
      status: "active"
    )
  end

  def geography(type, uid, name)
    Warehouse::InstitutionGeographySnapshot.create!(
      institution_release: @release,
      canonical_id: Warehouse::InstitutionGeographySnapshot.canonical_id_for(
        boundary_type: type, census_year: 2021, geo_uid: uid
      ),
      code_system: "#{type}_2021",
      geo_uid: uid,
      boundary_type: type,
      name_en: name,
      province_code: "35",
      census_year: 2021
    )
  end

  def csd_inventory_row(uid, name, type, province_code: "12")
    {
      geo_uid: uid,
      dguid: "2021A0005#{uid}",
      name_en: name,
      classification_type: type,
      province_code: province_code,
      area_sq_km: 1.0
    }
  end

  def create_pdf_asset(directory, name)
    bytes = "%PDF-1.4\n#{name}\n%%EOF\n"
    hash = Digest::SHA256.hexdigest(bytes)
    relative = "sha256/#{hash.first(2)}/#{hash}.pdf"
    path = File.join(directory, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes)
    { path: path, relative: relative, hash: hash, size: bytes.bytesize }
  end

  def create_asset(document, asset, role:, preferred: false)
    Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release,
      institution_document: document,
      content_sha256: asset.fetch(:hash),
      asset_role: role,
      preferred: preferred,
      download_url: "https://example.test/#{asset.fetch(:hash)}.pdf",
      retrieved_at: @release.published_at,
      archive_path: asset.fetch(:relative),
      mime_type: "application/pdf",
      byte_size: asset.fetch(:size),
      rights_status: "metadata_only"
    )
  end

  def write_builder_inputs(directory)
    base = {
      release_version: "2026-08-18",
      effective_on: "2026-08-18",
      geography_vintage: 2021,
      roster_source_url: "https://example.test/roster",
      geography_source_url: "https://example.test/geography",
      municipalities: [ {
        canonical_id: "ca/ns/example-town",
        official_name: "Town of Example",
        municipality_type: "Town",
        government_level: "municipal",
        website_url: "https://example.test/town",
        identifiers: [],
        statcan_geographies: []
      } ]
    }
    draft = raw_document("Draft Consolidated Financial Statements", "a" * 64, "draft.pdf")
    final = raw_document("Final Consolidated Financial Statements", "b" * 64, "final.pdf")
    annual = raw_document("2025 Annual Report", "c" * 64, "annual.pdf", type: "annual_report")
    batch_a_payload = {
      batch: "a", retrieved_at: "2026-08-18T12:00:00Z",
      municipalities: [ {
        canonical_id: "ca/ns/example-town",
        searched_locations: [ "https://example.test/a" ], gaps: [ "Earlier years unavailable" ],
        financial_statements: [ draft ]
      } ]
    }
    batch_b_payload = {
      batch: "b", retrieved_at: "2026-08-19T00:00:00Z",
      municipalities: [ {
        canonical_id: "ca/ns/example-town",
        searched_locations: [ "https://example.test/b" ], gaps: [],
        financial_statements: [ final ], annual_reports: [ annual ]
      } ]
    }
    paths = [ [ "base.json", base ], [ "batch-a.json", batch_a_payload ], [ "batch-b.json", batch_b_payload ] ].map do |name, payload|
      path = File.join(directory, name)
      File.write(path, JSON.pretty_generate(payload))
      path
    end
    paths
  end

  def raw_document(title, hash, filename, type: "financial_statements")
    {
      title: title,
      document_type: type,
      fiscal_period_start: "2024-04-01",
      fiscal_period_end: "2025-03-31",
      source_page_url: "https://example.test/finance",
      download_url: "https://example.test/#{filename}",
      retrieved_at: "2026-08-18T12:00:00Z",
      content_sha256: hash,
      archive_path: "sha256/#{hash.first(2)}/#{hash}.pdf",
      mime_type: "application/pdf",
      byte_size: 123,
      rights_status: "metadata_only"
    }
  end

  def build_manifest(base_path, batch_paths, output_path)
    Warehouse::InstitutionRelease::NovaScotiaMunicipalityManifestBuilder.new(
      base_path: base_path,
      batch_paths: batch_paths,
      output_path: output_path,
      release_version: "2026-08-19",
      published_at: "2026-08-19T00:00:00Z",
      verify_assets: false
    ).call
  end

  def importer_manifest(asset)
    {
      release_version: "2026-08-16",
      effective_on: "2026-08-16",
      schema_version: "1.0",
      published_at: "2026-08-16T00:00:00Z",
      source_retrieved_at: "2026-08-16T00:00:00Z",
      geography_vintage: 2021,
      attribution: "Example attribution",
      roster_source_url: "https://example.test/roster",
      geography_source_url: "https://example.test/geography",
      municipalities: [ {
        canonical_id: "ca/ns/example-town",
        official_name: "Town of Example",
        municipality_type: "Town",
        government_level: "municipal",
        website_url: "https://example.test/town",
        identifiers: [ { scheme: "statcan.csd", value: "1299999", preferred: true } ],
        statcan_geographies: [ { uid: "1299999", name: "Example" } ],
        documents: [ {
          canonical_id: "ca/ns/example-town/documents/financial-statements/2025/consolidated",
          document_type: "financial-statements",
          document_variant: "consolidated",
          title: "Financial Statements",
          fiscal_period_end: "2025-03-31",
          source_page_url: "https://example.test/town/finance",
          assets: [ {
            content_sha256: asset.fetch(:hash), asset_role: "final", preferred: true,
            download_url: "https://example.test/town/statement.pdf",
            retrieved_at: "2026-08-16T00:00:00Z",
            archive_path: asset.fetch(:relative), mime_type: "application/pdf",
            byte_size: asset.fetch(:size), rights_status: "metadata_only"
          } ]
        } ]
      } ]
    }
  end


  def province_metadata(code, statcan_code, name)
    {
      code: code,
      statcan_code: statcan_code,
      name_en: name,
      government_name_en: "Government of #{name}",
      website_url: "https://example.test/#{code}",
      source_languages: [ "en" ],
      source_license: "Example licence"
    }
  end
end
