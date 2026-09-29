-- VENDORED from BuildCanada/fact-factory, src/fact_factory/serve/api_schema.sql at 7a570c2
-- (PR #27, branch api-read-model). fact-factory owns this schema; york_factory only reads it.
-- The tests load it into their own database (test/support/fact_factory_api_database.rb), and
-- script/public_api/explain.rb into a benchmark one. To refresh after the read model changes:
--   { head -6 db/fact_factory_api/api_schema.sql; cat <fact-factory>/src/fact_factory/serve/api_schema.sql; } > tmp.sql
-- and update the commit above. Do not edit the statements below by hand.
-- The `api` schema: the allowlisted read model york_factory serves (docs/public-interface-design.md
-- on the public-interface-design branch, section 5.2; docs/RUNBOOK.md, "API read model").
--
-- This file is the contract for the public API (WS-D). fact-factory creates it with
-- serve.read_model.ensure_schema() before every build; every statement is idempotent. Every
-- column here must be listed in src/fact_factory/serve/allowlist.py, and nothing else may exist in
-- the schema: the blocking check api_columns_allowlisted compares the live schema with that list.
-- No column holds a street address, a full postal code, raw source JSON or a warehouse-only field.
--
-- Versioning: a row is one version, current in releases release_from <= N and (release_to IS NULL
-- or release_to > N); api.in_release(release_from, release_to, N) says so. api.releases lists the
-- releases the model serves; its row for N is the last statement of N's build transaction, so a
-- reader that sees release N in api.releases sees all of it. Unchanged rows are not copied.

CREATE SCHEMA IF NOT EXISTS api;

CREATE OR REPLACE FUNCTION api.in_release(release_from integer, release_to integer, release_id integer)
RETURNS boolean LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$$ SELECT $1 <= $3 AND ($2 IS NULL OR $2 > $3) $$;

-- A JSON value without the object keys matching a pattern, at any depth. The build removes
-- address keys (serve.allowlist.FORBIDDEN_KEYS) from roster attributes with it.
CREATE OR REPLACE FUNCTION api.without_keys(value jsonb, pattern text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS
$$
BEGIN
  IF jsonb_typeof(value) = 'object' THEN
    RETURN (SELECT coalesce(jsonb_object_agg(k, api.without_keys(v, pattern)), '{}'::jsonb)
            FROM jsonb_each(value) AS e(k, v) WHERE k !~* pattern);
  ELSIF jsonb_typeof(value) = 'array' THEN
    RETURN (SELECT coalesce(jsonb_agg(api.without_keys(v, pattern) ORDER BY i), '[]'::jsonb)
            FROM jsonb_array_elements(value) WITH ORDINALITY AS a(v, i));
  END IF;
  RETURN value;
END
$$;

-- One published registry release the read model serves.
CREATE TABLE IF NOT EXISTS api.releases (
  release_id integer PRIMARY KEY,
  published_at timestamptz NOT NULL,
  built_at timestamptz NOT NULL,
  code_revision text,
  build_version text,
  roster_captures jsonb NOT NULL,
  spending_snapshots jsonb NOT NULL,
  snapshot_basis text NOT NULL,
  counts jsonb NOT NULL,
  checks jsonb NOT NULL,
  build_seconds double precision
);

-- The newest release the model serves: "latest" in the API.
CREATE OR REPLACE FUNCTION api.latest_release() RETURNS integer LANGUAGE sql STABLE PARALLEL SAFE AS
$$ SELECT max(release_id) FROM api.releases $$;

-- One version of one entity (warehouse.entities).
CREATE TABLE IF NOT EXISTS api.entities (
  row_id text PRIMARY KEY,
  entity_id text NOT NULL,
  anchor text NOT NULL,
  entity_class text NOT NULL,
  subtype text,
  name text NOT NULL,
  name_fr text,
  aliases jsonb NOT NULL,
  jurisdiction text,
  status text,
  valid_from text,
  valid_to text,
  attributes jsonb NOT NULL,
  redirected_to text,
  content_sha256 text NOT NULL,
  source jsonb NOT NULL,
  recorded_at double precision NOT NULL,
  release_from integer NOT NULL,
  release_to integer
);
CREATE INDEX IF NOT EXISTS api_entities_entity ON api.entities (entity_id, release_from);
CREATE INDEX IF NOT EXISTS api_entities_class ON api.entities (entity_class, subtype, jurisdiction, release_from);
CREATE INDEX IF NOT EXISTS api_entities_redirected ON api.entities (redirected_to) WHERE redirected_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS api_entities_release_from ON api.entities (release_from);
CREATE INDEX IF NOT EXISTS api_entities_release_to ON api.entities (release_to) WHERE release_to IS NOT NULL;

-- One name, French name or alias of one entity version, normalized for exact search.
CREATE TABLE IF NOT EXISTS api.entity_names (
  row_id text NOT NULL,
  entity_id text NOT NULL,
  kind text NOT NULL,
  name text NOT NULL,
  normalized_name text,
  match_key text,
  normalization text NOT NULL,
  release_from integer NOT NULL,
  release_to integer,
  PRIMARY KEY (row_id, kind, name)
);
CREATE INDEX IF NOT EXISTS api_entity_names_match ON api.entity_names (match_key, release_from);
CREATE INDEX IF NOT EXISTS api_entity_names_entity ON api.entity_names (entity_id, release_from);
CREATE INDEX IF NOT EXISTS api_entity_names_release_to ON api.entity_names (release_to) WHERE release_to IS NOT NULL;

-- One version of one external identifier (warehouse.entity_identifiers).
CREATE TABLE IF NOT EXISTS api.identifiers (
  row_id text PRIMARY KEY,
  entity_id text NOT NULL,
  namespace text NOT NULL,
  value text NOT NULL,
  verified integer NOT NULL,
  vintage text,
  valid_from text,
  valid_to text,
  content_sha256 text NOT NULL,
  source jsonb NOT NULL,
  recorded_at double precision NOT NULL,
  release_from integer NOT NULL,
  release_to integer
);
CREATE INDEX IF NOT EXISTS api_identifiers_value ON api.identifiers (namespace, value, release_from);
CREATE INDEX IF NOT EXISTS api_identifiers_entity ON api.identifiers (entity_id, release_from);
CREATE INDEX IF NOT EXISTS api_identifiers_release_from ON api.identifiers (release_from);
CREATE INDEX IF NOT EXISTS api_identifiers_release_to ON api.identifiers (release_to) WHERE release_to IS NOT NULL;

-- One version of one relationship (warehouse.entity_relationships), lineage included.
CREATE TABLE IF NOT EXISTS api.relationships (
  row_id text PRIMARY KEY,
  subject_id text NOT NULL,
  predicate text NOT NULL,
  object_id text,
  object_ref text,
  attributes jsonb NOT NULL,
  valid_from text,
  valid_to text,
  content_sha256 text NOT NULL,
  source jsonb NOT NULL,
  recorded_at double precision NOT NULL,
  release_from integer NOT NULL,
  release_to integer
);
CREATE INDEX IF NOT EXISTS api_relationships_subject ON api.relationships (subject_id, predicate, release_from);
CREATE INDEX IF NOT EXISTS api_relationships_object ON api.relationships (object_id, predicate, release_from);
CREATE INDEX IF NOT EXISTS api_relationships_release_from ON api.relationships (release_from);
CREATE INDEX IF NOT EXISTS api_relationships_release_to ON api.relationships (release_to) WHERE release_to IS NOT NULL;

-- One version of one party on one spending row (warehouse.mention_occurrences). An individual's
-- raw_name, normalized_name and identifiers are blank; no row has a full postal code.
CREATE TABLE IF NOT EXISTS api.spending_parties (
  row_id text PRIMARY KEY,
  occurrence_id text NOT NULL,
  asset_key text NOT NULL,
  acquisition text NOT NULL,
  snapshot_id text NOT NULL,
  spending_row_id text NOT NULL,
  field text NOT NULL,
  position integer NOT NULL,
  party_kind text NOT NULL,
  kind_reason text,
  raw_name text,
  normalized_name text,
  identifiers jsonb,
  city text,
  province text,
  fsa text,
  country text,
  row_date text,
  fiscal_year integer,
  entity_id text,
  method text,
  reason text,
  candidates jsonb,
  create_reason text,
  rule_version text NOT NULL,
  content_sha256 text NOT NULL,
  recorded_at double precision NOT NULL,
  release_from integer NOT NULL,
  release_to integer
);
CREATE INDEX IF NOT EXISTS api_spending_parties_entity ON api.spending_parties (entity_id, release_from)
  WHERE entity_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS api_spending_parties_record ON api.spending_parties (asset_key, acquisition, spending_row_id);
CREATE INDEX IF NOT EXISTS api_spending_parties_occurrence ON api.spending_parties (occurrence_id, release_from);
CREATE INDEX IF NOT EXISTS api_spending_parties_release_from ON api.spending_parties (release_from);
CREATE INDEX IF NOT EXISTS api_spending_parties_release_to ON api.spending_parties (release_to)
  WHERE release_to IS NOT NULL;

-- One version of one spending source row, from the Iceberg snapshot the release pinned. Typed
-- columns only: raw_json, raw_xml and extra_json stay in the Iceberg table. recipient_postal_code
-- is the full code only when the row's recipient is an organization in the release; otherwise
-- (an individual, or no organization recipient) its forward sortation area, the first 3
-- characters uppercased (york_factory DECISIONS.md 20).
CREATE TABLE IF NOT EXISTS api.spending_records (
  spending_key text NOT NULL,
  asset_key text NOT NULL,
  source_key text NOT NULL,
  acquisition text NOT NULL,
  resource_id text NOT NULL,
  id text NOT NULL,
  external_id text,
  canonical_id text,
  source_occurrence bigint,
  record_type text,
  title text,
  description text,
  program text,
  payer text,
  payer_code text,
  recipient text,
  recipients jsonb,
  recipient_refs jsonb,
  research_org text,
  principal_investigator text,
  recipient_business_number text,
  recipient_type text,
  recipient_city text,
  recipient_postal_code text,
  province text,
  country text,
  amount numeric(38, 6),
  currency text,
  commitments_json jsonb,
  fiscal_year integer,
  date date,
  date_raw text,
  is_aggregated boolean,
  value_consistent boolean,
  revision_rank jsonb,
  source_url text,
  source_sha256 text,
  parser_version text,
  snapshot_id text NOT NULL,
  content_sha256 text NOT NULL,
  release_from integer NOT NULL,
  release_to integer,
  PRIMARY KEY (spending_key, release_from)
);
CREATE INDEX IF NOT EXISTS api_spending_records_row ON api.spending_records (asset_key, acquisition, id);
CREATE INDEX IF NOT EXISTS api_spending_records_payer ON api.spending_records (payer_code, fiscal_year);
CREATE INDEX IF NOT EXISTS api_spending_records_year ON api.spending_records (asset_key, fiscal_year);
CREATE INDEX IF NOT EXISTS api_spending_records_release_from ON api.spending_records (release_from);
CREATE INDEX IF NOT EXISTS api_spending_records_release_to ON api.spending_records (release_to)
  WHERE release_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS api_spending_records_current ON api.spending_records (asset_key, acquisition, spending_key)
  WHERE release_to IS NULL;

-- Entity x role x source x fiscal year x currency, per release, under the fixed aggregation rules
-- (serve.read_model.SUMMARY_SQL): linked live occurrences only, never summed across sources, the
-- highest-ranked revision per canonical_id, aggregate rows left out and counted, blank amounts
-- counted, never zero. Rebuilt for every release; old releases keep their rows.
CREATE TABLE IF NOT EXISTS api.spending_summary (
  release_id integer NOT NULL,
  entity_id text NOT NULL,
  role text NOT NULL,
  asset_key text NOT NULL,
  source_key text NOT NULL,
  fiscal_year integer,
  currency text,
  measure text NOT NULL,
  record_count integer NOT NULL,
  agreement_count integer NOT NULL,
  amount numeric(38, 6),
  amount_missing_count integer NOT NULL,
  aggregated_excluded integer NOT NULL,
  revisions_excluded integer NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS api_spending_summary_key ON api.spending_summary
  (release_id, entity_id, role, asset_key, coalesce(fiscal_year, -1), coalesce(currency, ''));

-- One bulk file of one release (serve.exports): the Parquet exports and their manifest.
CREATE TABLE IF NOT EXISTS api.release_exports (
  release_id integer NOT NULL,
  table_name text NOT NULL,
  object_key text NOT NULL,
  url text,
  sha256 text NOT NULL,
  rows bigint,
  bytes bigint NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (release_id, table_name)
);
