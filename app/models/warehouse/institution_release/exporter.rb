require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"

class Warehouse::InstitutionRelease::Exporter
  class ExportError < StandardError; end

  LICENSE_TEXT = "NOASSERTION - this release contains mixed-source metadata; see NOTICE.txt and sources.parquet."
  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")
  OOXML_MIME_TYPES = %w[
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  ].freeze

  attr_reader :release, :output_directory

  def initialize(release, output_directory:, duckdb_bin: ENV.fetch("DUCKDB_BIN", "duckdb"),
    asset_root: DEFAULT_ASSET_ROOT, verify_assets: true)
    @release = release
    @output_directory = Pathname(output_directory).expand_path
    @duckdb_bin = duckdb_bin
    @asset_root = Pathname(asset_root).expand_path
    @verify_assets = verify_assets
    @connection_string = postgres_connection_string
  end

  def export!
    release.validate_complete!
    validate_assets! if @verify_assets
    prepare_output_directory!
    export_parquet_files!
    write_supporting_files!
    write_manifest!
    write_checksums!
    output_directory
  end

  private

  def prepare_output_directory!
    raise ExportError, "refusing to overwrite release directory: #{output_directory}" if output_directory.exist?

    FileUtils.mkdir_p(output_directory)
  end

  def export_parquet_files!
    statements = export_queries.map do |filename, query|
      destination = sql_quote(output_directory.join(filename).to_s)
      remote_query = sql_quote(query.squish)
      <<~SQL
        COPY (
          SELECT * FROM postgres_query('ontology_source', '#{remote_query}')
        ) TO '#{destination}' (FORMAT PARQUET, COMPRESSION ZSTD);
      SQL
    end

    run_duckdb <<~SQL
      INSTALL postgres;
      LOAD postgres;
      ATTACH '#{sql_quote(@connection_string)}' AS ontology_source (TYPE POSTGRES, READ_ONLY);
      #{statements.join("\n")}
    SQL
  end

  def export_queries
    release_id = Integer(release.id)
    {
      "releases.parquet" => <<~SQL,
        SELECT version, effective_on, schema_version, published_at, geography_vintage, attribution,
          '#{sql_quote(LICENSE_TEXT)}'::text AS license_statement
        FROM warehouse.institution_releases
        WHERE id = #{release_id}
      SQL
      "sources.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          s.canonical_id AS source_id,
          s.publisher_name,
          s.title_en,
          s.title_fr,
          s.url,
          s.retrieved_at,
          s.license,
          s.attribution,
          ('en' = ANY(s.languages)) AS has_english,
          ('fr' = ANY(s.languages)) AS has_french
        FROM warehouse.institution_sources s
        JOIN warehouse.institution_releases r ON r.id = s.institution_release_id
        WHERE s.institution_release_id = #{release_id}
        ORDER BY s.canonical_id
      SQL
      "institutions.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          i.canonical_id,
          i.name_en,
          i.name_fr,
          i.website_url,
          i.institution_type,
          i.legal_form,
          i.government_level,
          i.status,
          i.contact_email,
          i.contact_phone,
          i.civic_address,
          i.mailing_address,
          i.active_from,
          i.active_to,
          (
            i.status = 'active'
            AND (i.active_from IS NULL OR i.active_from <= r.effective_on)
            AND (i.active_to IS NULL OR i.active_to >= r.effective_on)
          ) AS active_at_release,
          i.description_en,
          i.description_fr,
          i.fiscal_year_start_month,
          i.default_currency,
          src.canonical_id AS source_id
        FROM warehouse.institutions i
        JOIN warehouse.institution_releases r ON r.id = i.institution_release_id
        LEFT JOIN warehouse.institution_sources src ON src.id = i.institution_source_id
        WHERE i.institution_release_id = #{release_id}
        ORDER BY i.canonical_id
      SQL
      "identifiers.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          i.canonical_id AS institution_id,
          identifier.scheme,
          identifier.value,
          identifier.preferred,
          src.canonical_id AS source_id
        FROM warehouse.institution_identifiers identifier
        JOIN warehouse.institution_releases r ON r.id = identifier.institution_release_id
        JOIN warehouse.institutions i ON i.id = identifier.institution_id
        LEFT JOIN warehouse.institution_sources src ON src.id = identifier.institution_source_id
        WHERE identifier.institution_release_id = #{release_id}
        ORDER BY i.canonical_id, identifier.scheme, identifier.value
      SQL
      "relationships.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          source_i.canonical_id AS source_institution_id,
          target_i.canonical_id AS target_institution_id,
          rel.relationship_type,
          rel.primary AS is_primary,
          rel.ownership_percentage,
          rel.ownership_basis,
          rel.valid_from,
          rel.valid_to,
          rel.notes,
          src.canonical_id AS source_id
        FROM warehouse.institution_relationships rel
        JOIN warehouse.institution_releases r ON r.id = rel.institution_release_id
        JOIN warehouse.institutions source_i ON source_i.id = rel.source_institution_id
        JOIN warehouse.institutions target_i ON target_i.id = rel.target_institution_id
        LEFT JOIN warehouse.institution_sources src ON src.id = rel.institution_source_id
        WHERE rel.institution_release_id = #{release_id}
        ORDER BY source_i.canonical_id, rel.relationship_type, target_i.canonical_id, rel.valid_from
      SQL
      "geographies.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          g.canonical_id AS geography_id,
          g.code_system,
          g.geo_uid,
          g.boundary_type,
          g.classification_type,
          g.authority_status,
          g.name_en,
          g.name_fr,
          g.province_code,
          g.census_year,
          g.population,
          g.area_sq_km,
          ST_AsBinary(g.geometry::geometry) AS geometry_wkb,
          4326::integer AS geometry_srid
        FROM warehouse.institution_geography_snapshots g
        JOIN warehouse.institution_releases r ON r.id = g.institution_release_id
        WHERE g.institution_release_id = #{release_id}
        ORDER BY g.canonical_id
      SQL
      "institution_geographies.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          i.canonical_id AS institution_id,
          g.canonical_id AS geography_id,
          ig.role,
          ig.match_method,
          ig.confidence,
          ig.valid_from,
          ig.valid_to,
          ig.notes,
          src.canonical_id AS source_id
        FROM warehouse.institution_geographies ig
        JOIN warehouse.institution_releases r ON r.id = ig.institution_release_id
        JOIN warehouse.institutions i ON i.id = ig.institution_id
        JOIN warehouse.institution_geography_snapshots g ON g.id = ig.institution_geography_snapshot_id
        LEFT JOIN warehouse.institution_sources src ON src.id = ig.institution_source_id
        WHERE ig.institution_release_id = #{release_id}
        ORDER BY i.canonical_id, ig.role, g.canonical_id
      SQL
      "coverage.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          c.scope_id,
          c.subject,
          c.status,
          c.notes,
          c.source_url,
          src.canonical_id AS source_id
        FROM warehouse.institution_coverages c
        JOIN warehouse.institution_releases r ON r.id = c.institution_release_id
        LEFT JOIN warehouse.institution_sources src ON src.id = c.institution_source_id
        WHERE c.institution_release_id = #{release_id}
        ORDER BY c.scope_id, c.subject, c.status, c.id
      SQL
      "documents.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          d.canonical_id,
          i.canonical_id AS reporting_institution_id,
          src.canonical_id AS source_id,
          d.document_type,
          d.document_variant,
          d.title_en,
          d.title_fr,
          d.fiscal_period_start,
          d.fiscal_period_end,
          d.published_on,
          d.source_page_url,
          d.download_url,
          d.notes
        FROM warehouse.institution_documents d
        JOIN warehouse.institution_releases r ON r.id = d.institution_release_id
        JOIN warehouse.institutions i ON i.id = d.institution_id
        JOIN warehouse.institution_sources src ON src.id = d.institution_source_id
        WHERE d.institution_release_id = #{release_id}
        ORDER BY d.canonical_id
      SQL
      "document_assets.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          d.canonical_id AS document_id,
          a.content_sha256,
          a.asset_role,
          a.part_index,
          a.part_count,
          a.preferred,
          a.download_url,
          a.retrieved_at,
          CASE
            WHEN a.rights_status = 'redistributable' THEN 'assets/' || a.archive_path
          END AS archive_path,
          a.mime_type,
          a.byte_size,
          a.rights_status,
          a.page_locator
        FROM warehouse.institution_document_assets a
        JOIN warehouse.institution_releases r ON r.id = a.institution_release_id
        JOIN warehouse.institution_documents d ON d.id = a.institution_document_id
        WHERE a.institution_release_id = #{release_id}
        ORDER BY d.canonical_id, a.part_index NULLS FIRST, a.content_sha256
      SQL
      "financial_statement_extractions.parquet" => <<~SQL,
        SELECT
          r.version AS release_version,
          d.canonical_id || '#' || e.asset_sha256 || '#' || e.extractor_version AS extraction_id,
          d.canonical_id AS document_id,
          e.asset_sha256,
          e.fiscal_year_end,
          e.statement_basis,
          e.language,
          e.extractor_version,
          e.llm_model,
          e.status,
          e.check_results::text AS check_results_json,
          e.reviewed_by,
          e.reviewed_at,
          e.review_notes
        FROM warehouse.financial_statement_extractions e
        JOIN warehouse.institution_documents d
          ON d.institution_release_id = #{release_id}
          AND d.canonical_id = e.document_canonical_id
        JOIN warehouse.institution_document_assets a
          ON a.institution_document_id = d.id
          AND a.content_sha256 = e.asset_sha256
        JOIN warehouse.institution_releases r ON r.id = d.institution_release_id
        WHERE e.status IN ('extracted', 'approved')
        ORDER BY d.canonical_id, e.asset_sha256, e.extractor_version
      SQL
      "financial_statement_facts.parquet" => <<~SQL
        SELECT
          r.version AS release_version,
          d.canonical_id || '#' || e.asset_sha256 || '#' || e.extractor_version AS extraction_id,
          f.concept,
          f.value,
          f.raw_text,
          f.raw_label,
          f.scale,
          f.statement,
          f.source_page,
          f.column_year,
          f.extraction_confidence
        FROM warehouse.financial_statement_facts f
        JOIN warehouse.financial_statement_extractions e ON e.id = f.financial_statement_extraction_id
        JOIN warehouse.institution_documents d
          ON d.institution_release_id = #{release_id}
          AND d.canonical_id = e.document_canonical_id
        JOIN warehouse.institution_document_assets a
          ON a.institution_document_id = d.id
          AND a.content_sha256 = e.asset_sha256
        JOIN warehouse.institution_releases r ON r.id = d.institution_release_id
        WHERE e.status IN ('extracted', 'approved')
        ORDER BY d.canonical_id, e.asset_sha256, e.extractor_version, f.concept
      SQL
    }
  end

  def write_supporting_files!
    File.write(output_directory.join("postgres_schema.sql"), postgres_schema_sql)
    File.write(output_directory.join("load_into_postgres.sql"), load_sql)
    File.write(output_directory.join("LICENSE.txt"), "#{LICENSE_TEXT}\n")
    File.write(output_directory.join("NOTICE.txt"), notice_text)
  end

  def write_manifest!
    parquet_files = export_queries.keys.map do |filename|
      path = output_directory.join(filename)
      {
        name: filename,
        bytes: path.size,
        rows: parquet_row_count(path),
        sha256: Digest::SHA256.file(path).hexdigest
      }
    end
    manifest = {
      product: "canadian-public-institutions",
      release: release.version,
      effective_on: release.effective_on.iso8601,
      schema_version: release.schema_version,
      geography_vintage: release.geography_vintage,
      generated_at: release.published_at.iso8601,
      format: "parquet",
      compression: "zstd",
      duckdb_version: duckdb_version,
      minimum_postgresql_version: 15,
      license_statement: LICENSE_TEXT,
      license_file: "LICENSE.txt",
      notice_file: "NOTICE.txt",
      files: parquet_files
    }
    File.write(output_directory.join("manifest.json"), JSON.pretty_generate(manifest) << "\n")
  end

  def write_checksums!
    filenames = export_queries.keys + %w[
      postgres_schema.sql load_into_postgres.sql LICENSE.txt NOTICE.txt manifest.json
    ]
    contents = filenames.sort.map do |filename|
      "#{Digest::SHA256.file(output_directory.join(filename)).hexdigest}  #{filename}"
    end
    File.write(output_directory.join("checksums.sha256"), contents.join("\n") << "\n")
  end

  def parquet_row_count(path)
    stdout, stderr, status = Open3.capture3(
      @duckdb_bin, "-csv", "-noheader", "-c",
      "SELECT count(*) FROM read_parquet('#{sql_quote(path.to_s)}')"
    )
    raise ExportError, stderr.strip unless status.success?

    Integer(stdout.strip)
  end

  def duckdb_version
    stdout, stderr, status = Open3.capture3(@duckdb_bin, "--version")
    raise ExportError, stderr.strip unless status.success?

    stdout.strip
  rescue Errno::ENOENT
    raise ExportError, "DuckDB executable not found; set DUCKDB_BIN or install duckdb"
  end

  def run_duckdb(sql)
    _stdout, stderr, status = Open3.capture3(@duckdb_bin, stdin_data: sql)
    return if status.success?

    safe_error = stderr.to_s.gsub(@connection_string, "[REDACTED]")
    raise ExportError, "DuckDB export failed: #{safe_error.strip}"
  rescue Errno::ENOENT
    raise ExportError, "DuckDB executable not found; set DUCKDB_BIN or install duckdb"
  end

  def postgres_connection_string
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    values = {
      host: config[:host], port: config[:port], dbname: config[:database],
      user: config[:username], password: config[:password]
    }.compact
    values.map { |key, value| "#{key}=#{libpq_quote(value.to_s)}" }.join(" ")
  end

  def libpq_quote(value)
    return value if value.match?(/\A[a-zA-Z0-9_.:\/-]+\z/)

    "'#{value.gsub(/[\\']/) { |character| "\\#{character}" }}'"
  end

  def sql_quote(value)
    value.to_s.gsub("'", "''")
  end

  def validate_assets!
    release.institution_document_assets.find_each do |asset|
      candidate = @asset_root.join(asset.archive_path).expand_path
      root_prefix = "#{@asset_root.to_s.delete_suffix(File::SEPARATOR)}#{File::SEPARATOR}"
      raise ExportError, "archive escapes asset root: #{candidate}" unless candidate.to_s.start_with?(root_prefix)
      raise ExportError, "missing archive: #{candidate}" unless candidate.file?
      raise ExportError, "archive checksum mismatch: #{candidate}" unless Digest::SHA256.file(candidate).hexdigest == asset.content_sha256
      raise ExportError, "archive size mismatch: #{candidate}" unless candidate.size == asset.byte_size
      validate_asset_content!(asset, candidate)
    end
  end

  def validate_asset_content!(asset, candidate)
    case asset.mime_type
    when "application/pdf"
      raise ExportError, "archive is not a PDF: #{candidate}" unless candidate.binread(5) == "%PDF-"
    when *OOXML_MIME_TYPES
      raise ExportError, "archive is not an OOXML file: #{candidate}" unless candidate.binread(4) == "PK\x03\x04".b
      package_part = asset.mime_type.include?("wordprocessingml") ? "word/document.xml" : "xl/workbook.xml"
      raise ExportError, "archive MIME does not match OOXML content: #{candidate}" unless candidate.binread.include?(package_part)
    else
      raise ExportError, "unsupported archive MIME #{asset.mime_type.inspect}: #{candidate}"
    end
  end

  def notice_text
    source_notices = release.institution_sources.order(:canonical_id).map do |source|
      details = [ source.publisher_name, source.license, source.attribution, source.url ].compact_blank
      "- #{source.canonical_id}: #{details.join(' | ')}"
    end
    ([ release.attribution, "", LICENSE_TEXT, "", "Source notices:", *source_notices ].join("\n") << "\n")
  end

  def postgres_schema_sql
    <<~SQL
      -- Requires PostgreSQL 15 or newer.
      CREATE SCHEMA IF NOT EXISTS public_institutions;

      CREATE TABLE IF NOT EXISTS public_institutions.releases (
        version text PRIMARY KEY,
        effective_on date NOT NULL,
        schema_version text NOT NULL,
        published_at timestamp NOT NULL,
        geography_vintage integer NOT NULL,
        attribution text NOT NULL,
        license_statement text NOT NULL
      );

      CREATE TABLE IF NOT EXISTS public_institutions.sources (
        release_version text NOT NULL REFERENCES public_institutions.releases(version),
        source_id text NOT NULL,
        publisher_name text NOT NULL,
        title_en text,
        title_fr text,
        url text NOT NULL,
        retrieved_at timestamp NOT NULL,
        license text,
        attribution text,
        has_english boolean NOT NULL,
        has_french boolean NOT NULL,
        PRIMARY KEY (release_version, source_id)
      );

      CREATE TABLE IF NOT EXISTS public_institutions.institutions (
        release_version text NOT NULL REFERENCES public_institutions.releases(version),
        canonical_id text NOT NULL,
        name_en text,
        name_fr text,
        website_url text,
        institution_type text NOT NULL,
        legal_form text,
        government_level text NOT NULL,
        status text NOT NULL,
        contact_email text,
        contact_phone text,
        civic_address text,
        mailing_address text,
        active_from date,
        active_to date,
        active_at_release boolean NOT NULL,
        description_en text,
        description_fr text,
        fiscal_year_start_month integer,
        default_currency text,
        source_id text,
        PRIMARY KEY (release_version, canonical_id),
        FOREIGN KEY (release_version, source_id)
          REFERENCES public_institutions.sources(release_version, source_id)
      );

      CREATE TABLE IF NOT EXISTS public_institutions.identifiers (
        release_version text NOT NULL,
        institution_id text NOT NULL,
        scheme text NOT NULL,
        value text NOT NULL,
        preferred boolean NOT NULL,
        source_id text,
        FOREIGN KEY (release_version, institution_id)
          REFERENCES public_institutions.institutions(release_version, canonical_id),
        FOREIGN KEY (release_version, source_id)
          REFERENCES public_institutions.sources(release_version, source_id),
        UNIQUE NULLS NOT DISTINCT (release_version, scheme, value)
      );
      CREATE UNIQUE INDEX IF NOT EXISTS public_institution_identifiers_preferred
        ON public_institutions.identifiers (release_version, institution_id, scheme)
        WHERE preferred;

      CREATE TABLE IF NOT EXISTS public_institutions.relationships (
        release_version text NOT NULL,
        source_institution_id text NOT NULL,
        target_institution_id text NOT NULL,
        relationship_type text NOT NULL,
        is_primary boolean NOT NULL,
        ownership_percentage numeric(7,4),
        ownership_basis text,
        valid_from date,
        valid_to date,
        notes text,
        source_id text,
        FOREIGN KEY (release_version, source_institution_id)
          REFERENCES public_institutions.institutions(release_version, canonical_id),
        FOREIGN KEY (release_version, target_institution_id)
          REFERENCES public_institutions.institutions(release_version, canonical_id),
        FOREIGN KEY (release_version, source_id)
          REFERENCES public_institutions.sources(release_version, source_id),
        UNIQUE NULLS NOT DISTINCT
          (release_version, source_institution_id, target_institution_id, relationship_type, valid_from)
      );
      CREATE UNIQUE INDEX IF NOT EXISTS public_institution_relationships_primary_parent
        ON public_institutions.relationships (release_version, source_institution_id)
        WHERE is_primary;

      CREATE TABLE IF NOT EXISTS public_institutions.geographies (
        release_version text NOT NULL REFERENCES public_institutions.releases(version),
        geography_id text NOT NULL,
        code_system text NOT NULL,
        geo_uid text NOT NULL,
        boundary_type text NOT NULL,
        classification_type text,
        authority_status text NOT NULL,
        name_en text,
        name_fr text,
        province_code text,
        census_year integer NOT NULL,
        population integer,
        area_sq_km numeric,
        geometry_wkb bytea,
        geometry_srid integer NOT NULL,
        CHECK (authority_status IN ('legacy','not_applicable','verified','provisional','unresolved')),
        PRIMARY KEY (release_version, geography_id)
      );

      CREATE TABLE IF NOT EXISTS public_institutions.institution_geographies (
        release_version text NOT NULL,
        institution_id text NOT NULL,
        geography_id text NOT NULL,
        role text NOT NULL,
        match_method text NOT NULL,
        confidence numeric(5,4),
        valid_from date,
        valid_to date,
        notes text,
        source_id text,
        FOREIGN KEY (release_version, institution_id)
          REFERENCES public_institutions.institutions(release_version, canonical_id),
        FOREIGN KEY (release_version, geography_id)
          REFERENCES public_institutions.geographies(release_version, geography_id),
        FOREIGN KEY (release_version, source_id)
          REFERENCES public_institutions.sources(release_version, source_id),
        CHECK (role IN ('governs','administers','serves','headquartered_in')),
        CHECK (match_method IN ('legacy','authoritative_crosswalk','source_assertion','exact_identifier','exact_name','jurisdictional_fallback')),
        CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
        CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
        UNIQUE (release_version, institution_id, geography_id, role)
      );

      CREATE TABLE IF NOT EXISTS public_institutions.coverage (
        release_version text NOT NULL REFERENCES public_institutions.releases(version),
        scope_id text NOT NULL,
        subject text NOT NULL,
        status text NOT NULL,
        notes text NOT NULL,
        source_url text,
        source_id text,
        FOREIGN KEY (release_version, source_id)
          REFERENCES public_institutions.sources(release_version, source_id),
        CHECK (subject IN ('institutions','websites','geographies','relationships','financial-statements','annual-reports','statement-of-financial-information','financial-data-return','document-assets','csd-inventory','csd-authority-mapping')),
        CHECK (status IN ('complete','partial','not-searched','not-found','unavailable','failed')),
        UNIQUE (release_version, scope_id, subject)
      );

      CREATE TABLE IF NOT EXISTS public_institutions.documents (
        release_version text NOT NULL,
        canonical_id text NOT NULL,
        reporting_institution_id text NOT NULL,
        source_id text NOT NULL,
        document_type text NOT NULL,
        document_variant text NOT NULL,
        title_en text,
        title_fr text,
        fiscal_period_start date,
        fiscal_period_end date,
        published_on date,
        source_page_url text,
        download_url text,
        notes text,
        PRIMARY KEY (release_version, canonical_id),
        FOREIGN KEY (release_version, reporting_institution_id)
          REFERENCES public_institutions.institutions(release_version, canonical_id),
        FOREIGN KEY (release_version, source_id)
          REFERENCES public_institutions.sources(release_version, source_id)
      );

      CREATE TABLE IF NOT EXISTS public_institutions.document_assets (
        release_version text NOT NULL,
        document_id text NOT NULL,
        content_sha256 text NOT NULL,
        asset_role text NOT NULL,
        part_index integer,
        part_count integer,
        preferred boolean NOT NULL,
        download_url text NOT NULL,
        retrieved_at timestamp NOT NULL,
        archive_path text,
        mime_type text NOT NULL,
        byte_size bigint NOT NULL,
        rights_status text NOT NULL,
        page_locator text,
        PRIMARY KEY (release_version, document_id, content_sha256),
        FOREIGN KEY (release_version, document_id)
          REFERENCES public_institutions.documents(release_version, canonical_id)
      );
      CREATE UNIQUE INDEX IF NOT EXISTS public_institution_document_assets_preferred
        ON public_institutions.document_assets (release_version, document_id)
        WHERE preferred;

      CREATE TABLE IF NOT EXISTS public_institutions.financial_statement_extractions (
        release_version text NOT NULL,
        extraction_id text NOT NULL,
        document_id text NOT NULL,
        asset_sha256 text NOT NULL,
        fiscal_year_end date NOT NULL,
        statement_basis text NOT NULL,
        language text,
        extractor_version text NOT NULL,
        llm_model text,
        status text NOT NULL,
        check_results_json text NOT NULL,
        reviewed_by text,
        reviewed_at timestamp,
        review_notes text,
        PRIMARY KEY (release_version, extraction_id),
        FOREIGN KEY (release_version, document_id, asset_sha256)
          REFERENCES public_institutions.document_assets(release_version, document_id, content_sha256),
        CHECK (statement_basis IN ('consolidated','non_consolidated')),
        CHECK (language IS NULL OR language IN ('en','fr','bilingual')),
        CHECK (status IN ('extracted','approved'))
      );

      CREATE TABLE IF NOT EXISTS public_institutions.financial_statement_facts (
        release_version text NOT NULL,
        extraction_id text NOT NULL,
        concept text NOT NULL,
        value numeric(24,2) NOT NULL,
        raw_text text NOT NULL,
        raw_label text NOT NULL,
        scale integer NOT NULL,
        statement text NOT NULL,
        source_page integer NOT NULL,
        column_year text NOT NULL,
        extraction_confidence numeric(5,4),
        PRIMARY KEY (release_version, extraction_id, concept),
        FOREIGN KEY (release_version, extraction_id)
          REFERENCES public_institutions.financial_statement_extractions(release_version, extraction_id),
        CHECK (concept IN (
          'total_financial_assets','total_liabilities','net_financial_assets',
          'total_non_financial_assets','accumulated_surplus','opening_accumulated_surplus',
          'total_revenue','total_expenses','annual_surplus'
        )),
        CHECK (scale IN (1,1000,1000000)),
        CHECK (statement IN ('financial_position','operations','accumulated_surplus')),
        CHECK (source_page > 0),
        CHECK (extraction_confidence IS NULL OR extraction_confidence BETWEEN 0 AND 1)
      );
    SQL
  end

  def load_sql
    <<~SQL
      -- Run with DuckDB from inside the release directory. This loader is insert-only:
      -- an existing release version is an error, preventing silent recuts.
      INSTALL postgres;
      LOAD postgres;
      ATTACH 'REPLACE_WITH_POSTGRES_CONNECTION_STRING' AS target (TYPE POSTGRES);

      BEGIN TRANSACTION;

      INSERT INTO target.public_institutions.releases
        SELECT * FROM read_parquet('releases.parquet');
      INSERT INTO target.public_institutions.sources
        SELECT * FROM read_parquet('sources.parquet');
      INSERT INTO target.public_institutions.institutions
        SELECT * FROM read_parquet('institutions.parquet');
      INSERT INTO target.public_institutions.identifiers
        SELECT * FROM read_parquet('identifiers.parquet');
      INSERT INTO target.public_institutions.relationships
        SELECT * FROM read_parquet('relationships.parquet');
      INSERT INTO target.public_institutions.geographies
        SELECT * FROM read_parquet('geographies.parquet');
      INSERT INTO target.public_institutions.institution_geographies
        SELECT * FROM read_parquet('institution_geographies.parquet');
      INSERT INTO target.public_institutions.coverage
        SELECT * FROM read_parquet('coverage.parquet');
      INSERT INTO target.public_institutions.documents
        SELECT * FROM read_parquet('documents.parquet');
      INSERT INTO target.public_institutions.document_assets
        SELECT * FROM read_parquet('document_assets.parquet');
      INSERT INTO target.public_institutions.financial_statement_extractions
        SELECT * FROM read_parquet('financial_statement_extractions.parquet');
      INSERT INTO target.public_institutions.financial_statement_facts
        SELECT * FROM read_parquet('financial_statement_facts.parquet');

      COMMIT;
    SQL
  end
end
