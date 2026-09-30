# Query plans of the public API's main queries against a generated read model
# of representative size (fact-factory docs/public-interface-design.md §5.2):
# EXPLAIN (ANALYZE, BUFFERS) of the SQL the query objects really send, on
# fact-factory's schema as it is, then with any indexes this script proposes
# for WS-B (PROPOSED_INDEXES).
#
#   RAILS_ENV=test bin/rails runner script/public_api/explain.rb                  # 2M spending rows
#   SCALE=0.2 RAILS_ENV=test bin/rails runner script/public_api/explain.rb        # a quick run
#   KEEP=1 ...                                                                    # reuse a generated database
#
# It writes a separate database, york_factory_fact_factory_api_bench, on the
# server of the test database, and never touches the test fixtures.
module ExplainPublicApi
  SCALE = Float(ENV.fetch("SCALE", "1"))
  DATABASE = "york_factory_fact_factory_api_bench".freeze
  SIZES = {
    entities: 200_000, identifiers: 400_000, relationships: 100_000, spending_records: 2_000_000
  }.transform_values { |n| (n * SCALE).to_i }

  # Indexes the queries want and fact-factory's api_schema.sql does not have.
  # Empty since 6b3034e, which added every index this script proposed (the
  # revision, unlinked-name, proposed-candidate, full-text, name and amount
  # indexes). Add one here to measure it before asking WS-B for it.
  PROPOSED_INDEXES = {}.freeze

  module_function

  def run
    config = FactFactoryRecord.connection_db_config.configuration_hash
    params = { host: config[:host], port: config[:port], user: config[:username], password: config[:password] }.compact
    generate(params) unless ENV["KEEP"] && exists?(params)
    FactFactoryRecord.establish_connection(config.merge(database: DATABASE))
    FactFactory::ReleaseQuery.reset!
    FactFactory::SearchQuery.reset!
    report("fact-factory api_schema.sql as it is")
    return if PROPOSED_INDEXES.empty?

    admin = PG.connect(**params, dbname: DATABASE)
    PROPOSED_INDEXES.each_value { |sql| admin.exec(sql.sub("CREATE INDEX", "CREATE INDEX IF NOT EXISTS")) }
    admin.exec("ANALYZE")
    admin.close
    FactFactory::ReleaseQuery.reset!
    report("with the proposed WS-B indexes")
  end

  def exists?(params)
    PG.connect(**params, dbname: "postgres").then { |c| c.exec_params("SELECT 1 FROM pg_database WHERE datname = $1", [ DATABASE ]).ntuples.positive?.tap { c.close } }
  end

  def generate(params)
    admin = PG.connect(**params, dbname: "postgres")
    admin.exec("DROP DATABASE IF EXISTS #{DATABASE}")
    admin.exec("CREATE DATABASE #{DATABASE}")
    admin.close
    c = PG.connect(**params, dbname: DATABASE)
    c.exec(File.read(Rails.root.join("db/fact_factory_api/api_schema.sql")))
    c.exec("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    c.exec("CREATE INDEX IF NOT EXISTS api_entity_names_trgm ON api.entity_names USING gin (normalized_name gin_trgm_ops)")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      c.exec(GENERATE.gsub(":entities", SIZES[:entities].to_s).gsub(":identifiers", SIZES[:identifiers].to_s)
        .gsub(":relationships", SIZES[:relationships].to_s).gsub(":records", SIZES[:spending_records].to_s))
      # As fact-factory's build: is_latest_revision per slice (LATEST_SQL),
      # fresh statistics, then the summaries.
      c.exec(LATEST)
      c.exec("ANALYZE")
      c.exec(File.read(Rails.root.join("db/fact_factory_api/summary.sql")).gsub("$1", "11"))
      c.exec(File.read(Rails.root.join("db/fact_factory_api/counterparties.sql")).gsub("$1", "11"))
      c.exec("ANALYZE api.spending_summary")
      c.exec("ANALYZE api.spending_counterparties")
    end
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    counts = %w[entities identifiers relationships spending_records spending_parties spending_summary spending_counterparties].map do |t|
      "#{t} #{c.exec("SELECT count(*) FROM api.#{t}").getvalue(0, 0)}"
    end
    puts "Generated in #{time.round(1)} s: #{counts.join(', ')}"
    c.close
  end

  # [label, lambda] per query: each runs the real query object once, and its
  # SQL is captured and explained.
  def queries
    e = "01#{'0' * 20}1234"
    busy = "01#{'0' * 20}0007" # a payer on many rows
    [
      [ "listEntities (default page)", -> { FactFactory::EntityQuery.new(release: 11).page(filters: {}, sort: "id", limit: 50) } ],
      [ "listEntities sort=name", -> { FactFactory::EntityQuery.new(release: 11).page(filters: {}, sort: "name", limit: 50) } ],
      [ "listEntities class+jurisdiction", -> { FactFactory::EntityQuery.new(release: 11).page(filters: { "class" => "government_org", "jurisdiction" => "ca-on" }, sort: "id", limit: 50) } ],
      [ "getEntity", -> { FactFactory::EntityQuery.new(release: 11).find(e) } ],
      [ "listEntityRelationships (both)", -> { FactFactory::EntityQuery.new(release: 11).relationships(e, limit: 50) } ],
      [ "getEntityLineage", -> { FactFactory::EntityQuery.new(release: 11).lineage(e, direction: "predecessors", max_depth: 10, limit: 50) } ],
      [ "resolveIdentifier", -> { FactFactory::EntityQuery.new(release: 11).holders("ca.cra.bn9", "000001234") } ],
      [ "searchEntities exact", -> { FactFactory::SearchQuery.new(release: 11).page(q: "Entity 1234", mode: "exact", limit: 20) } ],
      [ "searchEntities fuzzy", -> { FactFactory::SearchQuery.new(release: 11).page(q: "Entty 1234", mode: "fuzzy", limit: 20) } ],
      [ "listSpending (default page)", -> { spending.page(filters: {}, sort: "id", limit: 50) } ],
      [ "listSpending source+fiscal_year", -> { spending.page(filters: { "source" => [ "proactive_grants" ], "fiscal_year" => "2019-20" }, sort: "id", limit: 50) } ],
      [ "listSpending sort=-amount", -> { spending.page(filters: {}, sort: "-amount", limit: 50) } ],
      [ "listSpending recipient=", -> { spending.page(filters: { "recipient" => e }, sort: "id", limit: 50) } ],
      [ "listSpending payer= (busy payer)", -> { spending.page(filters: { "payer" => busy }, sort: "id", limit: 50) } ],
      [ "listSpending q=", -> { spending.page(filters: { "q" => "project 1234" }, sort: "id", limit: 50) } ],
      [ "listSpending latest_revision_only", -> { spending.page(filters: { "latest_revision_only" => true }, sort: "id", limit: 50) } ],
      [ "listSpending count=exact source=", -> { spending.count(filters: { "source" => [ "transfer_payments" ] }) } ],
      [ "getSpendingRecord + parties + revision", lambda {
        r = spending.page(filters: {}, sort: "id", limit: 1).first
        spending.parties([ r ])
        spending.latest_revisions([ r ])
      } ],
      [ "listEntitySpending (busy payer)", -> { spending.page(filters: {}, sort: "id", limit: 50, entity: busy, role: "payer") } ],
      [ "listEntitySpending include_proposed", -> { spending.page(filters: {}, sort: "id", limit: 50, entity: e, role: "recipient", include_proposed: true) } ],
      [ "getEntitySpendingSummary", -> { spending.summary(busy, role: "payer", by_year: true) } ],
      [ "summary unlinked_occurrences count", -> { spending.unlinked_count(e, role: "recipient") } ],
      [ "summary group_by=counterparty", -> { spending.counterparty_summary(e, role: "recipient", by_year: false) } ]
    ]
  end

  def spending = FactFactory::SpendingQuery.new(release: 11)

  def report(title)
    puts "\n## #{title}\n\n| Query | ms (warm) | Plan |\n|---|---:|---|"
    queries.each do |label, query|
      statements = capture { attempt(&query) }
      attempt(&query) # warm the cache once
      statements.each_with_index do |sql, i|
        plan = begin
          FactFactoryRecord.connection.select_values("EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) #{sql}")
        rescue ActiveRecord::QueryCanceled
          puts "| #{label}#{statements.size > 1 ? " (#{i + 1})" : ''} | > statement timeout | (422 query_too_broad) |"
          next
        end
        ms = plan.grep(/Execution Time/).first.to_s[/[\d.]+/].to_f
        shape = plan.grep(/(Scan|Join|Sort|Aggregate|Limit)/).first(4).map { |l| l.strip.sub(/\s+\(cost.*/, "").sub(/^->\s*/, "") }.join(" / ")
        puts "| #{label}#{statements.size > 1 ? " (#{i + 1})" : ''} | #{format("%.2f", ms)} | #{shape.gsub('|', '\\|')} |"
      end
    end
  end

  def attempt
    yield
  rescue ActiveRecord::QueryCanceled
    nil
  end

  def capture
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql]
      statements << sql if sql.match?(/\A\s*(SELECT|WITH)/i) && !sql.include?("pg_") && payload[:name] != "SCHEMA"
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # fact-factory's LATEST_SQL over the whole generated table, per slice.
  LATEST = <<~SQL.freeze
    UPDATE api.spending_records s SET is_latest_revision = ranked.latest FROM (
      SELECT ctid AS row, revision_rank IS NULL OR row_number() OVER (
        PARTITION BY asset_key, acquisition, canonical_id ORDER BY revision_rank DESC NULLS LAST, id DESC, resource_id, source_occurrence) = 1 AS latest
      FROM api.spending_records) ranked
    WHERE s.ctid = ranked.row
  SQL

  GENERATE = <<~SQL.freeze
    INSERT INTO api.releases VALUES
      (10, '2026-09-20', '2026-09-20', 'bench', 'registry-build-v4', '{}', '{}', 'recorded', '{}', '{}', 1),
      (11, '2026-09-27', '2026-09-27', 'bench', 'registry-build-v4', '{}', '{}', 'recorded', '{}', '{}', 1);

    INSERT INTO api.entities
    SELECT md5('e' || i), '01' || lpad(i::text, 24, '0'), 'bench:' || i,
      (ARRAY['government_org','organization','organization','organization','jurisdiction'])[1 + i % 5],
      (ARRAY['municipal_government','registered_charity','business','non_profit','province'])[1 + i % 5],
      'Entity ' || i, NULL, '[]', (ARRAY['ca','ca-on','ca-ab','ca-bc','ca-qc'])[1 + i % 5], 'active',
      NULL, NULL, '{}', NULL, md5('c' || i), '{"origin":"resolution"}', 1758823331, CASE WHEN i % 20 = 0 THEN 11 ELSE 10 END, NULL
    FROM generate_series(1, :entities) i;

    INSERT INTO api.entity_names
    SELECT row_id, entity_id, 'name', name, lower(name), lower(name), 'names-v2', release_from, release_to FROM api.entities;

    INSERT INTO api.identifiers
    SELECT md5('i' || i), '01' || lpad((1 + i % :entities)::text, 24, '0'),
      CASE WHEN i % 2 = 0 THEN 'ca.cra.bn9' ELSE 'ca.statcan.csd_uid' END, lpad((1 + i % :entities)::text, 9, '0'),
      1, NULL, NULL, NULL, md5('ic' || i), '{}', 1758823331, 10, NULL
    FROM generate_series(1, :identifiers) i;

    INSERT INTO api.relationships
    SELECT md5('r' || i), '01' || lpad((1 + (i * 7) % :entities)::text, 24, '0'),
      CASE WHEN i % 20 = 0 THEN 'succeeded_by' ELSE 'located_within' END,
      '01' || lpad((1 + (i * 13) % :entities)::text, 24, '0'), NULL, '{}', NULL, NULL, md5('rc' || i), '{}', 1758823331, 10, NULL
    FROM generate_series(1, :relationships) i;

    INSERT INTO api.spending_records
    SELECT lpad(upper(to_hex(i)), 26, '0'),
      'sources/ca/' || s.path, s.key, CASE WHEN i % 50 = 0 THEN 'archive_import' ELSE 'live' END, md5('res' || (i % 40)), md5('row' || i),
      md5('x' || i), md5('can' || (i / 2)), 1, 'grant', 'Project ' || i, 'Description of project ' || i, 'Program ' || (i % 300),
      'Department ' || (i % 500), 'pc' || (i % 500), 'Recipient ' || (i % 150000), '[]', '[]', NULL, NULL, NULL, NULL, NULL,
      'T0L 0H0', 'AB', 'CA', CASE WHEN i % 17 = 0 THEN NULL ELSE (i % 1000000)::numeric + 0.5 END, 'CAD', NULL,
      2005 + i % 21, DATE '2005-04-01' + (i % 7600), NULL, i % 97 = 0, NULL, jsonb_build_array(i % 2), NULL,
      'https://open.canada.ca/', md5('sha' || (i % 40)), 'spending-iceberg-v5', '1', md5('rc' || i), 10, NULL
    FROM generate_series(1, :records) i
    CROSS JOIN LATERAL (SELECT (ARRAY['proactive_grants','proactive_contracts','transfer_payments','nserc_awards'])[1 + i % 4] AS key,
      (ARRAY['tbs/proactive_grants','tbs/proactive_contracts','pspc/transfer_payments','nserc/awards'])[1 + i % 4] AS path) s;

    INSERT INTO api.spending_parties
    SELECT md5('pp' || r.spending_key || f.field), md5('po' || r.spending_key || f.field), r.asset_key, r.acquisition, '1', r.id, f.field, 0,
      'organization', NULL, f.name, lower(f.name), '{}', NULL, NULL, NULL, 'CA', NULL, r.fiscal_year,
      CASE WHEN f.linked THEN f.entity END, CASE WHEN f.linked THEN 'exact_name' WHEN f.proposed THEN 'exact_name' END,
      CASE WHEN f.linked THEN NULL WHEN f.proposed THEN 'proposed' ELSE 'no_candidate' END,
      CASE WHEN f.proposed THEN jsonb_build_array(f.entity) ELSE '[]' END, NULL, 'bench', md5('pc' || r.spending_key || f.field), 1758823331, 10, NULL
    FROM api.spending_records r
    CROSS JOIN LATERAL (VALUES
      ('payer', 'Department ' || (('x' || substr(r.id, 1, 6))::bit(24)::int % 500), '01' || lpad((1 + ('x' || substr(r.id, 1, 6))::bit(24)::int % 500)::text, 24, '0'), true, false),
      ('recipient', r.recipient, '01' || lpad((1 + ('x' || substr(r.id, 7, 6))::bit(24)::int % :entities)::text, 24, '0'),
        ('x' || substr(r.id, 13, 2))::bit(8)::int < 154, ('x' || substr(r.id, 13, 2))::bit(8)::int BETWEEN 154 AND 160)
    ) f(field, name, entity, linked, proposed);
  SQL
end

ExplainPublicApi.run
