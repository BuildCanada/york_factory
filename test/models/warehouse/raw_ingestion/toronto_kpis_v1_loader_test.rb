require "test_helper"
require "sqlite3"
require "tmpdir"

class Warehouse::RawIngestion::TorontoKpisV1LoaderTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir
    @sqlite_path = File.join(@tmpdir, "scrape_fixture.db")
    build_fixture_sqlite(@sqlite_path)

    ensure_toronto_seed

    source = Warehouse::Source.find_or_create_by!(name: "kpis-loader-test-#{SecureRandom.hex(3)}") do |s|
      s.url = "file://#{@sqlite_path}"
      s.format = "sqlite"
    end
    @raw = Warehouse::RawIngestion.create!(
      source: source,
      fetched_at: Time.current,
      raw_file_path: @sqlite_path,
      checksum: Digest::SHA256.file(@sqlite_path).hexdigest,
      status: "pending"
    )
  end

  teardown do
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  test "loads documents, measures, citations end-to-end" do
    counts = @raw.toronto_kpis_v1_loader.load
    assert_equal 1, counts[:documents]
    assert_equal 2, counts[:measures]
    assert_equal 3, counts[:citations]
    assert_equal "complete", @raw.reload.status

    doc = Warehouse::KpiDocument.find_by!(doc_url: "https://example.com/budget-2024.pdf")
    assert_equal 2024, doc.fiscal_year
    assert_equal "discovered_at_fallback", doc.published_at_source

    permits = Warehouse::Measure.find_by!(slug: "permits-issued")
    assert_equal "Permits Issued", permits.canonical_name
    assert_equal 2, permits.citations.count

    pct = Warehouse::Measure.find_by!(slug: "permits-issued-pct")
    assert_equal 1, pct.citations.count
  end

  test "v1 fractional percentage bug is cleaned up (only for the % unit)" do
    counts = @raw.toronto_kpis_v1_loader.load
    assert_equal 1, counts[:ratio_cleanups]

    # Citation with raw v1 value 0.50 (bugged) → store as 50 * scale(0.01) = 0.5
    measure = Warehouse::Measure.find_by!(slug: "permits-issued-pct")
    bugged_citation = measure.citations.find_by!(measurement_year: 2024)
    assert_in_delta 0.5, bugged_citation.value_numeric, 1e-6
    assert_includes bugged_citation.notes.to_s, "v1-cleanup"
  end

  test "rerun is idempotent" do
    @raw.toronto_kpis_v1_loader.load

    # second load shouldn't double-insert (unique constraints catch it)
    source2 = Warehouse::Source.find_or_create_by!(name: "kpis-loader-test2-#{SecureRandom.hex(3)}") do |s|
      s.url = "file://#{@sqlite_path}"
      s.format = "sqlite"
    end
    raw2 = Warehouse::RawIngestion.create!(
      source: source2,
      fetched_at: Time.current,
      raw_file_path: @sqlite_path,
      checksum: "test-different-#{SecureRandom.hex(8)}",
      status: "pending"
    )
    counts = raw2.toronto_kpis_v1_loader.load
    assert_equal 1, counts[:documents]
    assert_equal 2, counts[:measures]
    assert_equal 0, counts[:citations]   # all duplicates
  end

  private

  def build_fixture_sqlite(path)
    db = SQLite3::Database.new(path)
    db.execute_batch(<<~SQL)
      CREATE TABLE documents (
        id INTEGER PRIMARY KEY,
        year INTEGER NOT NULL,
        source_page TEXT,
        doc_url TEXT UNIQUE NOT NULL,
        doc_title TEXT,
        doc_type TEXT,
        agency_department TEXT,
        filename TEXT,
        filepath TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        fetched_at TEXT,
        http_status INTEGER,
        file_size INTEGER,
        content_type TEXT,
        error TEXT,
        discovered_at TEXT
      );
      CREATE TABLE kpis (
        id INTEGER PRIMARY KEY,
        agency_department TEXT NOT NULL,
        service_category TEXT,
        measure_name TEXT NOT NULL,
        unit TEXT,
        description TEXT,
        first_seen_year INTEGER,
        last_seen_year INTEGER
      );
      CREATE TABLE kpi_values (
        id INTEGER PRIMARY KEY,
        kpi_id INTEGER NOT NULL,
        measurement_year INTEGER NOT NULL,
        value_type TEXT NOT NULL,
        value_numeric REAL,
        value_text TEXT,
        document_id INTEGER,
        source_doc_year INTEGER,
        page_number INTEGER,
        notes TEXT
      );

      INSERT INTO documents (id, year, doc_url, doc_title, agency_department, discovered_at)
      VALUES (1, 2024, 'https://example.com/budget-2024.pdf', '2024 Budget', 'City Planning', '2024-03-15');

      INSERT INTO kpis (id, agency_department, measure_name, unit, first_seen_year, last_seen_year)
      VALUES
        (1, 'City Planning', 'Permits Issued',       'count', 2020, 2024),
        (2, 'City Planning', 'Permits Issued (pct)', '%',     2020, 2024);

      INSERT INTO kpi_values (id, kpi_id, measurement_year, value_type, value_numeric, document_id)
      VALUES
        (1, 1, 2024, 'actual', 1234.0, 1),
        (2, 1, 2025, 'target', 1500.0, 1),
        (3, 2, 2024, 'actual', 0.5, 1);
    SQL
    db.close
  end

  def ensure_toronto_seed
    Warehouse::Jurisdiction.find_or_create_by!(code: "TOR-ON") do |j|
      j.name = "City of Toronto"
      j.slug = "toronto"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    toronto = Warehouse::Jurisdiction.find_by!(slug: "toronto")

    # Minimal: only the unit symbols + the city-planning org used in the fixture.
    Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    Warehouse::Unit.find_or_create_by!(symbol: "%")     { |u| u.kind = "ratio";    u.base_unit = "ratio"; u.scale = 0.01 }

    org = Warehouse::Organization.find_or_create_by!(jurisdiction_id: toronto.id, slug: "city-planning") do |o|
      o.canonical_name = "City Planning"
    end
    Warehouse::OrganizationAlias.find_or_create_by!(organization: org, alias_name: "City Planning")
  end
end
