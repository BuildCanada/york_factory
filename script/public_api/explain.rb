# Query plans of the public API's main queries against a generated fact_factory
# schema of representative size (fact-factory docs/public-interface-design.md
# §5.2; production on 2026-10-01: about 85k entities, 4M live spending rows and
# 12M occurrences): EXPLAIN (ANALYZE, BUFFERS) of the SQL the query objects
# really send, first on fact-factory's schema as it is (db/fact_factory/schema.sql),
# then with the indexes this script proposes (PROPOSED_INDEXES).
#
#   RAILS_ENV=test bin/rails runner script/public_api/explain.rb                  # 2M spending rows
#   SCALE=0.05 RAILS_ENV=test bin/rails runner script/public_api/explain.rb       # a quick run
#   KEEP=1 ...                                                                    # reuse a generated database
#
# It writes a separate database, york_factory_fact_factory_bench (PostGIS
# needed), on the server of the test database, and never touches the fixtures.
module ExplainPublicApi
  SCALE = Float(ENV.fetch("SCALE", "1"))
  DATABASE = "york_factory_fact_factory_bench".freeze
  SIZES = { entities: 200_000, identifiers: 400_000, relationships: 100_000, records: 2_000_000 }.transform_values { |n| (n * SCALE).to_i }
  # The four sources the generated spending rows are spread over, one live
  # publication each, at spending versions 1 to 4.
  SOURCES = %w[proactive_grants proactive_contracts transfer_payments nserc_awards].freeze

  # Indexes the queries want and fact-factory's schema does not have.
  PROPOSED_INDEXES = {
    "full-text q on /spending" =>
      "CREATE INDEX bench_records_text ON fact_factory.spending_records USING gin (to_tsvector('simple', #{FactFactory::SpendingQuery::TEXT.gsub('r.', '')}))",
    "proposed links of an entity (include_proposed)" =>
      "CREATE INDEX bench_occurrences_proposed ON fact_factory.mention_occurrences ((CAST(candidates AS jsonb)->>0)) WHERE reason = 'proposed'"
  }.freeze

  module_function

  def run
    config = FactFactoryRecord.connection_db_config.configuration_hash
    params = { host: config[:host], port: config[:port], user: config[:username], password: config[:password] }.compact
    generate(params) unless ENV["KEEP"] && exists?(params)
    FactFactoryRecord.establish_connection(config.merge(database: DATABASE))
    FactFactory::RevisionQuery.reset!
    report("fact-factory's schema as it is")
    admin = PG.connect(**params, dbname: DATABASE)
    PROPOSED_INDEXES.each_value { |sql| admin.exec(sql.sub("CREATE INDEX", "CREATE INDEX IF NOT EXISTS")) }
    admin.exec("ANALYZE")
    admin.close
    FactFactory::RevisionQuery.reset!
    report("with the proposed indexes")
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
    c.exec("CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public")
    c.exec(File.read(Rails.root.join("db/fact_factory/schema.sql")))
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sql = GENERATE.gsub(":entities", SIZES[:entities].to_s).gsub(":identifiers", SIZES[:identifiers].to_s)
      .gsub(":relationships", SIZES[:relationships].to_s).gsub(":records", SIZES[:records].to_s)
      .gsub(":assets", SOURCES.map { |s| c.escape_literal(PublicApi::Catalog.source(s).asset) }.join(", "))
      .gsub(":sources", SOURCES.map { |s| c.escape_literal(s) }.join(", "))
    c.exec(sql)
    # As fact-factory's derived build: fresh statistics, the live publications
    # of the build, then the summaries.
    c.exec("ANALYZE")
    c.exec("CREATE TEMP TABLE derived_pubs AS SELECT 'n'::text AS state, CASE source_key #{SOURCES.map { |s| "WHEN '#{s}' THEN '#{PublicApi::Catalog.source(s).asset}'" }.join(' ')} END AS asset_key, id AS publication_id FROM fact_factory.spending_publications")
    %w[summary counterparties].each { |f| c.exec(File.read(Rails.root.join("db/fact_factory/#{f}.sql")).gsub(/(?<!:):n\b/, "30")) }
    c.exec("ANALYZE")
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    counts = %w[entities entity_identifiers entity_relationships spending_records mention_occurrences spending_summary spending_counterparties].map do |t|
      "#{t} #{c.exec("SELECT count(*) FROM fact_factory.#{t}").getvalue(0, 0)}"
    end
    puts "Generated in #{time.round(1)} s: #{counts.join(', ')}"
    c.close
  end

  # [label, lambda] per query: each runs the real query object once, and its
  # SQL is captured and explained.
  def queries
    e = "01#{'0' * 20}1234"
    busy = "01#{'0' * 20}0007" # a payer on many rows
    spending = -> { FactFactory::SpendingQuery.new(revision: 30) }
    entities = -> { FactFactory::EntityQuery.new(revision: 30) }
    [
      [ "listEntities (default page)", -> { entities.().page(filters: {}, sort: "id", limit: 50) } ],
      [ "listEntities sort=name", -> { entities.().page(filters: {}, sort: "name", limit: 50) } ],
      [ "listEntities class+jurisdiction", -> { entities.().page(filters: { "class" => "government_org", "jurisdiction" => "ca-on" }, sort: "id", limit: 50) } ],
      [ "getEntity", -> { entities.().find(e) } ],
      [ "listEntityRelationships (both)", -> { entities.().relationships(e, limit: 50) } ],
      [ "getEntityLineage", -> { entities.().lineage(e, direction: "predecessors", max_depth: 10, limit: 50) } ],
      [ "resolveIdentifier", -> { entities.().holders("ca.cra.bn9", "000001234") } ],
      [ "searchEntities", -> { FactFactory::SearchQuery.new(revision: 30).page(q: "Entity 1234", mode: "exact", limit: 20) } ],
      [ "revision slices (once per revision)", -> { FactFactory::SpendingSlices.load(30) } ],
      [ "listSpending (default page)", -> { spending.().page(filters: {}, sort: "id", limit: 50) } ],
      [ "listSpending source+fiscal_year", -> { spending.().page(filters: { "source" => [ "proactive_grants" ], "fiscal_year" => "2019-20" }, sort: "id", limit: 50) } ],
      [ "listSpending sort=-amount", -> { spending.().page(filters: {}, sort: "-amount", limit: 50) } ],
      [ "listSpending recipient=", -> { spending.().page(filters: { "recipient" => e }, sort: "id", limit: 50) } ],
      [ "listSpending payer= (busy payer)", -> { spending.().page(filters: { "payer" => busy }, sort: "id", limit: 50) } ],
      [ "listSpending q=", -> { spending.().page(filters: { "q" => "project 1234" }, sort: "id", limit: 50) } ],
      [ "listSpending latest_revision_only", -> { spending.().page(filters: { "latest_revision_only" => true }, sort: "id", limit: 50) } ],
      [ "listSpending count=exact source=", -> { spending.().count(filters: { "source" => [ "transfer_payments" ] }) } ],
      [ "getSpendingRecord + parties + revision", lambda {
        q = spending.()
        r = q.page(filters: {}, sort: "id", limit: 1).first
        q.find(r.spending_key)
        q.parties([ r ])
        q.latest_revisions([ r ])
      } ],
      [ "listEntitySpending (busy payer)", -> { spending.().page(filters: {}, sort: "id", limit: 50, entity: busy, role: "payer") } ],
      [ "listEntitySpending include_proposed", -> { spending.().page(filters: {}, sort: "id", limit: 50, entity: e, role: "recipient", include_proposed: true) } ],
      [ "getEntitySpendingSummary (busy payer)", -> { spending.().summary(busy, role: "payer", by_year: true) } ],
      [ "summary group_by=counterparty", -> { spending.().counterparty_summary(busy, role: "payer", by_year: false) } ],
      [ "summary unlinked_occurrences count", -> { spending.().unlinked_count(e, role: "recipient") } ]
    ]
  end

  def report(title)
    puts "\n## #{title}\n\n| Query | ms (warm) | Plan |\n|---|---:|---|"
    queries.each do |label, query|
      statements = capture(slices: label.start_with?("revision slices")) { attempt(&query) }
      attempt(&query) # warm the cache once
      statements.each_with_index do |sql, i|
        name = "#{label}#{statements.size > 1 ? " (#{i + 1})" : ''}"
        plan = begin
          FactFactoryRecord.connection.select_values("EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) #{sql}")
        rescue ActiveRecord::QueryCanceled
          puts "| #{name} | > statement timeout | (422 query_too_broad) |"
          next
        end
        ms = plan.grep(/Execution Time/).first.to_s[/[\d.]+/].to_f
        shape = plan.grep(/(Scan|Join|Sort|Aggregate|Limit)/).first(4).map { |l| l.strip.sub(/\s+\(cost.*/, "").sub(/^->\s*/, "") }.join(" / ")
        puts "| #{name} | #{format('%.2f', ms)} | #{shape.gsub('|', '\\|')} |"
      end
    end
  end

  def attempt
    yield
  rescue ActiveRecord::QueryCanceled
    nil
  end

  def capture(slices: false)
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      binds = Array(payload[:type_casted_binds].respond_to?(:call) ? payload[:type_casted_binds].call : payload[:type_casted_binds])
      sql = payload[:sql].gsub(/\$(\d+)/) { FactFactoryRecord.connection.quote(binds[Regexp.last_match(1).to_i - 1]) }
      next unless sql.match?(/\A\s*(SELECT|WITH)/i) && !sql.include?("pg_") && payload[:name] != "SCHEMA"
      next if !slices && sql.match?(/\A\s*SELECT .*FROM "?fact_factory"?\."?(registry_revisions|spending_publications)"?\b/m) # loaded once per revision in production

      statements << sql
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  GENERATE = <<~SQL.freeze
    INSERT INTO fact_factory.registry_revisions (id, kind, state, reason, inputs, created_at, committed_at)
    SELECT 30, 'resolution', 'committed', 'bench', json_build_object('slices', json_object_agg(a, v::text)), 1790000000, 1790000000
    FROM unnest(ARRAY[:assets]) WITH ORDINALITY AS t(a, v);

    INSERT INTO fact_factory.spending_publications (id, release_id, source_key, acquisition, resource_id, source_sha256, source_url,
      parser_version, observed_at, row_count, staged_at, version, committed_at)
    SELECT v, md5('rel' || v), s, 'live', md5('res' || s), md5('sha' || s), 'https://open.canada.ca/', 'spending-iceberg-v5', 1790000000,
      :records / 4, 1790000000, v, 1790000000
    FROM unnest(ARRAY[:sources]) WITH ORDINALITY AS t(s, v);

    INSERT INTO fact_factory.derived_builds VALUES (30, NULL, '{}', '{}', '[]', 'derived-v1', 1790000000, 1);

    INSERT INTO fact_factory.entities
    SELECT md5('e' || i), '01' || lpad(i::text, 24, '0'), 'bench:' || i,
      (ARRAY['government_org','organization','organization','organization','jurisdiction'])[1 + i % 5],
      (ARRAY['municipal_government','registered_charity','business','non_profit','province'])[1 + i % 5],
      'Entity ' || i, NULL, '[]', (ARRAY['ca','ca-on','ca-ab','ca-bc','ca-qc'])[1 + i % 5], 'active',
      NULL, NULL, '{}', NULL, md5('c' || i), '{"origin":"resolution"}', 1758823331, 30, NULL
    FROM generate_series(1, :entities) i;

    INSERT INTO fact_factory.entity_names
    SELECT row_id, 'name', name, entity_id, lower(name), lower(name), 'names-v2', revision_id, retired_revision_id FROM fact_factory.entities;

    INSERT INTO fact_factory.entity_identifiers
    SELECT md5('i' || i), '01' || lpad((1 + i % :entities)::text, 24, '0'),
      CASE WHEN i % 2 = 0 THEN 'ca.cra.bn9' ELSE 'ca.statcan.csd_uid' END, lpad((1 + i % :entities)::text, 9, '0'),
      1, NULL, NULL, NULL, md5('ic' || i), '{}', 1758823331, 30, NULL
    FROM generate_series(1, :identifiers) i;

    INSERT INTO fact_factory.entity_relationships
    SELECT md5('r' || i), '01' || lpad((1 + (i * 7) % :entities)::text, 24, '0'),
      CASE WHEN i % 20 = 0 THEN 'succeeded_by' ELSE 'located_within' END,
      '01' || lpad((1 + (i * 13) % :entities)::text, 24, '0'), NULL, '{}', NULL, NULL, md5('rc' || i), '{}', 1758823331, 30, NULL
    FROM generate_series(1, :relationships) i;

    INSERT INTO fact_factory.spending_records (publication_id, row_number, id, spending_key, external_id, canonical_id, source_key,
      acquisition, resource_id, source_url, source_sha256, parser_version, record_type, title, description, payer, payer_code, recipient,
      currency, province, country, program, revision_rank_json, amount, fiscal_year, source_occurrence, is_aggregated, date)
    SELECT 1 + i % 4, i, md5('row' || i), lpad(upper(to_hex(i)), 26, '0'), md5('x' || i), md5('can' || (i / 2)),
      (ARRAY[:sources])[1 + i % 4], 'live', md5('res' || (ARRAY[:sources])[1 + i % 4]), 'https://open.canada.ca/', md5('sha'), 'spending-iceberg-v5',
      'grant', 'Project ' || i, 'Description of project ' || i, 'Department ' || (i % 500), 'pc' || (i % 500), 'Recipient ' || (i % 150000),
      'CAD', 'AB', 'CA', 'Program ' || (i % 300), '[' || (i % 2) || ']',
      CASE WHEN i % 17 = 0 THEN NULL ELSE (i % 1000000)::numeric + 0.5 END, 2005 + i % 21, 1, i % 97 = 0, DATE '2005-04-01' + (i % 7600)
    FROM generate_series(1, :records) i;

    INSERT INTO fact_factory.mention_occurrences (row_id, occurrence_id, source_key, snapshot_id, spending_row_id, field, position, raw_name,
      normalized_name, fiscal_year, identifiers, party_kind, entity_id, method, reason, candidates, rule_version, content_sha256, source,
      recorded_at, revision_id)
    SELECT md5('o' || r.spending_key || f.field), md5('oc' || r.spending_key || f.field),
      (ARRAY[:assets])[1 + (r.row_number % 4)], '1', r.id, f.field, 0, f.name, lower(f.name), r.fiscal_year, '{}', 'organization',
      CASE WHEN f.linked THEN f.entity END, CASE WHEN f.linked OR f.proposed THEN 'exact_name' END,
      CASE WHEN f.linked THEN NULL WHEN f.proposed THEN 'proposed' ELSE 'no_candidate' END,
      CASE WHEN f.proposed THEN json_build_array(f.entity) ELSE '[]'::json END, 'bench', md5('c' || r.spending_key || f.field),
      '{"origin":"resolution"}', 1758823331, 30
    FROM fact_factory.spending_records r
    CROSS JOIN LATERAL (VALUES
      ('payer', 'Department ' || (r.row_number % 500), '01' || lpad((1 + r.row_number % 500)::text, 24, '0'), true, false),
      ('recipient', r.recipient, '01' || lpad((1 + (r.row_number * 7) % :entities)::text, 24, '0'), r.row_number % 10 < 6, r.row_number % 10 = 6)
    ) f(field, name, entity, linked, proposed);
  SQL
end

ExplainPublicApi.run
