require_relative "fact_factory/fixtures"

# The test database for the fact_factory connection: fact-factory's schema
# (db/fact_factory/schema.sql, vendored from fact-factory) with the rows of
# FactFactoryFixtures, and the derived summaries built by fact-factory's own
# SQL (db/fact_factory/summary.sql and counterparties.sql). Loaded once per
# change of those files, before the tests fork, under an advisory lock; every
# parallel worker then reads the same database (it has database_tasks: false,
# so Rails doesn't copy it per worker, and the connection is read-only).
#
# It needs a PostgreSQL server with PostGIS (the elections geometry columns), as
# the primary test database already does (DATABASE_URL in CI).
module FactFactoryDatabase
  ROOT = Rails.root.join("db/fact_factory")
  SCHEMA = ROOT.join("schema.sql")
  SUMMARY = ROOT.join("summary.sql")
  COUNTERPARTIES = ROOT.join("counterparties.sql")
  FIXTURES = File.expand_path("fact_factory/fixtures.rb", __dir__)
  LOCK = 7_302_119_012

  module_function

  def prepare!
    config = FactFactoryRecord.connection_db_config.configuration_hash
    conn = connect(config)
    conn.exec("SET default_transaction_read_only = off")
    conn.exec("SELECT pg_advisory_lock(#{LOCK})")
    load!(conn) unless loaded?(conn)
  ensure
    conn&.exec("SELECT pg_advisory_unlock(#{LOCK})")
    conn&.close
  end

  def digest
    Digest::SHA256.hexdigest([ SCHEMA, SUMMARY, COUNTERPARTIES, FIXTURES, __FILE__ ].map { |f| File.read(f) }.join)
  end

  def loaded?(conn)
    conn.exec("SELECT digest FROM public.york_factory_fixture_state").getvalue(0, 0) == digest
  rescue PG::UndefinedTable
    false
  end

  def load!(conn)
    conn.transaction do |c|
      c.exec("CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public")
      c.exec("DROP SCHEMA IF EXISTS fact_factory CASCADE")
      c.exec(File.read(SCHEMA))
      types = column_types(c)
      FactFactoryFixtures.tables.each { |table, rows| insert(c, table, rows, types.fetch(table)) }
      FactFactoryFixtures.derived_builds.each { |build| derive(c, build) }
      c.exec("CREATE TABLE IF NOT EXISTS public.york_factory_fixture_state (digest text NOT NULL)")
      c.exec("TRUNCATE public.york_factory_fixture_state")
      c.exec_params("INSERT INTO public.york_factory_fixture_state VALUES ($1)", [ digest ])
    end
    conn.exec("ANALYZE")
  end

  # The derived summaries at a build's revision, as fact-factory's
  # derived.build_revision writes them: the live publications of the build's
  # slices in derived_pubs, then SUMMARY_SQL and COUNTERPARTY_SQL for every
  # entity. A later build retires the earlier build's rows and writes its own
  # (fact-factory recomputes only the affected entities; recomputing all of them
  # gives the same rows as of each revision).
  def derive(c, build)
    n = build[:revision_id]
    c.exec("DROP TABLE IF EXISTS derived_pubs")
    c.exec("CREATE TEMP TABLE derived_pubs (state text, asset_key text, publication_id bigint)")
    build[:slices].each do |asset, version|
      source_key = FactFactoryFixtures::SOURCE_KEYS.fetch(asset)
      c.exec_params(<<~SQL, [ asset, source_key, version.to_i ])
        INSERT INTO derived_pubs SELECT 'n', $1, id FROM fact_factory.spending_publications
        WHERE source_key = $2 AND acquisition = 'live' AND version IS NOT NULL AND version <= $3
          AND (replaced_version IS NULL OR replaced_version > $3)
      SQL
    end
    %w[spending_summary spending_counterparties].each do |table|
      c.exec("UPDATE fact_factory.#{table} SET retired_revision_id = #{n} WHERE retired_revision_id IS NULL AND revision_id < #{n}")
    end
    # The revision as a literal, as psycopg2 sends it: a server-side parameter gets a generic plan.
    [ SUMMARY, COUNTERPARTIES ].each { |file| c.exec(File.read(file).gsub(/(?<!:):n\b/, n.to_s)) }
  end

  # {table => {column => udt_name}}, to encode arrays as PostgreSQL arrays and
  # everything else structured as JSON.
  def column_types(c)
    c.exec("SELECT table_name, column_name, udt_name FROM information_schema.columns WHERE table_schema = 'fact_factory'")
      .each_with_object(Hash.new { |h, k| h[k] = {} }) { |r, out| out[r["table_name"]][r["column_name"]] = r["udt_name"] }
  end

  def insert(c, table, rows, types)
    rows.each do |row|
      columns = row.keys.map(&:to_s)
      placeholders = columns.each_index.map { |i| "$#{i + 1}" }.join(", ")
      values = row.values.zip(columns).map { |v, col| encode(v, types.fetch(col)) }
      c.exec_params("INSERT INTO fact_factory.#{table} (#{columns.join(', ')}) VALUES (#{placeholders})", values)
    end
  end

  def encode(value, type)
    case value
    when nil then nil
    when Array then type.start_with?("_") ? PG::TextEncoder::Array.new.encode(value) : JSON.generate(value)
    when Hash then JSON.generate(value)
    else value.to_s
    end
  end

  def connect(config)
    params = { host: config[:host], port: config[:port], user: config[:username], password: config[:password] }.compact
    database = config.fetch(:database)
    PG.connect(**params, dbname: database)
  rescue PG::ConnectionBad => e
    raise unless e.message.include?("does not exist")

    admin = PG.connect(**params, dbname: "postgres")
    admin.exec("CREATE DATABASE #{admin.quote_ident(database)}")
    admin.close
    PG.connect(**params, dbname: database)
  end
end

FactFactoryDatabase.prepare!
