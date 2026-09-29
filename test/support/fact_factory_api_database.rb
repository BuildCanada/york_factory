require_relative "fact_factory_api/fixtures"

# The test database for the fact_factory_api connection: fact-factory's `api`
# schema (db/fact_factory_api/api_schema.sql, vendored from fact-factory) with
# the rows of FactFactoryApiFixtures. Loaded once per change of the schema or
# the fixtures, before the tests fork, under an advisory lock; every parallel
# worker then reads the same database (it has database_tasks: false, so Rails
# doesn't copy it per worker, and the connection is read-only).
#
# It needs only a PostgreSQL server the primary test database also uses
# (DATABASE_URL in CI); pg_trgm is used when available, as in fact-factory.
module FactFactoryApiDatabase
  SCHEMA = Rails.root.join("db/fact_factory_api/api_schema.sql")
  FIXTURES = File.expand_path("fact_factory_api/fixtures.rb", __dir__)
  LOCK = 7_302_119_011

  # fact-factory's own SUMMARY_SQL, vendored: the summary rows the API serves
  # are built by the read model's rules, not a copy of them.
  SUMMARY = Rails.root.join("db/fact_factory_api/summary.sql")

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
    Digest::SHA256.hexdigest([ SCHEMA, SUMMARY, FIXTURES, __FILE__ ].map { |f| File.read(f) }.join)
  end

  def loaded?(conn)
    conn.exec("SELECT digest FROM public.york_factory_fixture_state").getvalue(0, 0) == digest
  rescue PG::UndefinedTable
    false
  end

  def load!(conn)
    conn.transaction do |c|
      c.exec("DROP SCHEMA IF EXISTS api CASCADE")
      c.exec(File.read(SCHEMA))
      trigram(c)
      FactFactoryApiFixtures.tables.each { |table, rows| insert(c, table, rows) }
      # The release as a literal, as psycopg2 sends it: a server-side $1 gets a generic plan.
      [ 10, 11 ].each { |n| c.exec(File.read(SUMMARY).gsub("$1", n.to_s)) }
      c.exec("CREATE TABLE IF NOT EXISTS public.york_factory_fixture_state (digest text NOT NULL)")
      c.exec("TRUNCATE public.york_factory_fixture_state")
      c.exec_params("INSERT INTO public.york_factory_fixture_state VALUES ($1)", [ digest ])
    end
    conn.exec("ANALYZE")
  end

  # As fact-factory's ensure_schema: the trigram index where pg_trgm exists.
  def trigram(c)
    c.exec("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    c.exec("CREATE INDEX IF NOT EXISTS api_entity_names_trgm ON api.entity_names USING gin (normalized_name gin_trgm_ops)")
  rescue PG::Error
    nil
  end

  def insert(c, table, rows)
    return if rows.empty?

    columns = rows.first.keys
    rows.each do |row|
      raise "#{table} rows have different columns" unless row.keys == columns

      placeholders = columns.each_index.map { |i| "$#{i + 1}" }.join(", ")
      c.exec_params("INSERT INTO api.#{table} (#{columns.join(', ')}) VALUES (#{placeholders})", row.values.map { |v| encode(v) })
    end
  end

  def encode(value)
    case value
    when Hash, Array then JSON.generate(value)
    when nil then nil
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

FactFactoryApiDatabase.prepare!
