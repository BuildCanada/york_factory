-- VENDORED: the fact_factory schema as BuildCanada/fact-factory's db.initialize() creates it, at
-- fact-factory f0d4918 (main, after the 2026-10-01 cut-over). york_factory never runs this against
-- fact-factory's database: the public API reads that database as the read-only api_reader role.
-- The tests load it into their own database (test/support/fact_factory_database.rb), as does
-- script/public_api/explain.rb. It needs PostGIS (the elections geometry columns). To refresh, from
-- a fact-factory checkout, against a scratch database with PostGIS:
--   FACT_FACTORY_DATABASE_URL=postgresql+psycopg2:///scratch python -c 'from fact_factory import db; db.initialize()'
--   pg_dump -s -n fact_factory --no-owner --no-privileges scratch
-- and replace everything below this header, updating the commit above.
--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5 (Homebrew)
-- Dumped by pg_dump version 17.5 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: fact_factory; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA fact_factory;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ai_review_answers; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.ai_review_answers (
    pair_sha256 character varying NOT NULL,
    unit_id character varying NOT NULL,
    pair json NOT NULL,
    run_id character varying NOT NULL,
    revision_id integer NOT NULL,
    state character varying NOT NULL,
    outcome character varying,
    ref character varying,
    confidence double precision,
    evidence text,
    payload json NOT NULL,
    attempts integer NOT NULL,
    usage json NOT NULL,
    answered_at double precision NOT NULL
);


--
-- Name: ai_review_units; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.ai_review_units (
    unit_id character varying NOT NULL,
    payload json NOT NULL,
    generator character varying NOT NULL,
    revision_id integer NOT NULL,
    recorded_at double precision NOT NULL
);


--
-- Name: ai_spend; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.ai_spend (
    run_id character varying NOT NULL,
    state character varying NOT NULL,
    mode character varying NOT NULL,
    pilot integer,
    revision_id integer NOT NULL,
    pair json NOT NULL,
    units integer NOT NULL,
    occurrences integer NOT NULL,
    budget_cad double precision NOT NULL,
    ceiling_cad double precision NOT NULL,
    usd_cad double precision NOT NULL,
    rate_date character varying NOT NULL,
    projected json NOT NULL,
    reserved_cad double precision NOT NULL,
    actual_usd double precision,
    actual_cad double precision,
    usage json,
    result json,
    created_at double precision NOT NULL,
    finished_at double precision,
    budget_usd double precision,
    ceiling_usd double precision,
    reserved_usd double precision
);


--
-- Name: artifacts; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.artifacts (
    sha256 character varying NOT NULL,
    size bigint NOT NULL,
    storage_key text NOT NULL,
    created_at double precision NOT NULL
);


--
-- Name: catalog_history; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.catalog_history (
    id integer NOT NULL,
    index_sha256 character varying NOT NULL,
    content_sha256 character varying NOT NULL,
    visible_from double precision NOT NULL
);


--
-- Name: catalog_history_id_seq; Type: SEQUENCE; Schema: fact_factory; Owner: -
--

CREATE SEQUENCE fact_factory.catalog_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: catalog_history_id_seq; Type: SEQUENCE OWNED BY; Schema: fact_factory; Owner: -
--

ALTER SEQUENCE fact_factory.catalog_history_id_seq OWNED BY fact_factory.catalog_history.id;


--
-- Name: corporation_detail_archives; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.corporation_detail_archives (
    sha256 character varying NOT NULL,
    shard character varying NOT NULL,
    records integer NOT NULL,
    bytes bigint NOT NULL,
    created_at double precision NOT NULL
);


--
-- Name: corporation_detail_plan; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.corporation_detail_plan (
    corporation_number character varying NOT NULL,
    tier integer NOT NULL,
    shard character varying NOT NULL,
    capture_id character varying NOT NULL,
    bn9 character varying,
    roster_status character varying,
    planned_at double precision NOT NULL
);


--
-- Name: corporation_details; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.corporation_details (
    corporation_number character varying NOT NULL,
    fetched_at double precision,
    http_status integer,
    sha256 character varying,
    raw bytea,
    outcome character varying,
    corporation_id character varying,
    status character varying,
    act text,
    bn9 character varying,
    incorporated_on character varying,
    dissolved_on character varying,
    amalgamated_on character varying,
    discontinued_on character varying,
    last_annual_return_year integer,
    names jsonb,
    activities jsonb,
    annual_returns jsonb,
    parser_version character varying,
    archive_sha256 character varying,
    attempts integer,
    error text,
    error_status integer,
    error_at double precision,
    error_raw bytea
);


--
-- Name: corporation_directors; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.corporation_directors (
    corporation_number character varying NOT NULL,
    "position" integer NOT NULL,
    name text NOT NULL,
    address text,
    address_lines jsonb NOT NULL,
    page_sha256 character varying NOT NULL,
    fetched_at double precision NOT NULL
);


--
-- Name: corporation_pages; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.corporation_pages (
    corporation_number character varying NOT NULL,
    fetched_at double precision,
    http_status integer,
    sha256 character varying,
    raw bytea,
    outcome character varying,
    directors integer,
    significant_control integer,
    isc_updated_on character varying,
    isc_note text,
    parser_version character varying,
    archive_sha256 character varying,
    attempts integer,
    error text,
    error_status integer,
    error_at double precision,
    error_raw bytea
);


--
-- Name: corporation_significant_control; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.corporation_significant_control (
    corporation_number character varying NOT NULL,
    "position" integer NOT NULL,
    current integer NOT NULL,
    name text NOT NULL,
    address_label text,
    address text,
    address_lines jsonb NOT NULL,
    interest text,
    holds_shares text,
    control text,
    holding text,
    start_date character varying,
    end_date character varying,
    fields jsonb NOT NULL,
    withheld text,
    page_sha256 character varying NOT NULL,
    fetched_at double precision NOT NULL
);


--
-- Name: derived_builds; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.derived_builds (
    revision_id integer NOT NULL,
    previous_revision_id integer,
    slices jsonb NOT NULL,
    counts jsonb NOT NULL,
    checks jsonb NOT NULL,
    build_version character varying NOT NULL,
    built_at double precision NOT NULL,
    build_seconds double precision
);


--
-- Name: documents; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.documents (
    id character varying NOT NULL,
    institution_id character varying,
    source_key character varying,
    document_type character varying,
    title text,
    year integer,
    url text,
    sha256 character varying,
    metadata json NOT NULL,
    state character varying NOT NULL,
    text_sha256 character varying,
    parser_version character varying,
    indexed_revision character varying,
    acquisition character varying,
    updated_at double precision NOT NULL,
    rejected_reason character varying,
    scope character varying,
    collector character varying,
    source_category text
);


--
-- Name: elections_boundary_sets; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_boundary_sets (
    id character varying NOT NULL,
    jurisdiction character varying NOT NULL,
    kind character varying NOT NULL,
    kind_as_shown text,
    district_set_id character varying,
    legal_instrument text,
    gazetted_on character varying,
    in_force_from character varying,
    in_force_to character varying,
    source_url text,
    capture_sha256 character varying
);


--
-- Name: elections_candidacies; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_candidacies (
    id character varying NOT NULL,
    contest_id character varying NOT NULL,
    ballot_name text NOT NULL,
    normalized_name text NOT NULL,
    legal_name text,
    party_key character varying,
    party_as_shown text,
    status character varying NOT NULL,
    incumbent boolean,
    residence_address text,
    residence_city text,
    residence_province character varying,
    residence_postal_code character varying,
    agents jsonb DEFAULT '[]'::jsonb NOT NULL,
    declared_result character varying,
    first_seen_capture character varying NOT NULL,
    last_seen_capture character varying NOT NULL,
    status_changed_at double precision,
    person_id character varying
);


--
-- Name: elections_candidate_contacts; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_candidate_contacts (
    candidacy_id character varying NOT NULL,
    kind character varying NOT NULL,
    platform character varying DEFAULT ''::character varying NOT NULL,
    value text NOT NULL,
    source_url text NOT NULL,
    capture_sha256 character varying,
    linked_from_url text,
    evidence_quote text,
    found_by character varying NOT NULL,
    status character varying NOT NULL,
    note text,
    checked_at double precision
);


--
-- Name: elections_captures; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_captures (
    sha256 character varying NOT NULL,
    kind character varying NOT NULL,
    url text NOT NULL,
    bytes bigint NOT NULL,
    content_type character varying,
    first_retrieved_at double precision NOT NULL,
    last_retrieved_at double precision NOT NULL,
    metadata json NOT NULL
);


--
-- Name: elections_contact_research; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_contact_research (
    pair_sha256 character varying NOT NULL,
    candidacy_id character varying NOT NULL,
    pair json NOT NULL,
    run_id character varying NOT NULL,
    state character varying NOT NULL,
    rounds integer NOT NULL,
    pages json NOT NULL,
    proposals json NOT NULL,
    usage json NOT NULL,
    error text,
    answered_at double precision NOT NULL
);


--
-- Name: elections_contests; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_contests (
    id character varying NOT NULL,
    election_id character varying NOT NULL,
    office_id character varying,
    district_id character varying NOT NULL,
    seats integer NOT NULL,
    method character varying NOT NULL,
    status character varying NOT NULL,
    voting_day character varying,
    question_number integer,
    question_text text,
    question_text_fr text,
    threshold_as_shown text
);


--
-- Name: elections_districts; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_districts (
    id character varying NOT NULL,
    boundary_set_id character varying NOT NULL,
    code character varying NOT NULL,
    name_as_shown text NOT NULL,
    geometry public.geometry(MultiPolygon,4326)
);


--
-- Name: elections_elections; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_elections (
    id character varying NOT NULL,
    jurisdiction character varying NOT NULL,
    administrator text NOT NULL,
    kind character varying NOT NULL,
    called_on character varying,
    voting_day character varying NOT NULL,
    return_day character varying,
    nominations_close_at character varying,
    registration_deadline_at character varying,
    mail_request_deadline_at character varying,
    mail_return_deadline_at character varying,
    advance_voting_starts_at character varying,
    advance_voting_ends_at character varying,
    polls_open_at character varying,
    polls_close_at character varying,
    voting_notes text,
    where_to_vote_url text,
    source_url text,
    capture_sha256 character varying
);


--
-- Name: elections_offices; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_offices (
    id character varying NOT NULL,
    title text NOT NULL,
    title_fr text,
    body_name text NOT NULL,
    body_level character varying NOT NULL,
    jurisdiction character varying NOT NULL,
    source_url text
);


--
-- Name: elections_polling_areas; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_polling_areas (
    id character varying NOT NULL,
    boundary_set_id character varying NOT NULL,
    district_id character varying NOT NULL,
    code character varying NOT NULL,
    parent_id character varying,
    geometry public.geometry(MultiPolygon,4326)
);


--
-- Name: elections_result_reports; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_result_reports (
    id character varying NOT NULL,
    election_id character varying NOT NULL,
    stage character varying NOT NULL,
    polls_reported integer,
    polls_total integer,
    published_at character varying,
    published_at_as_shown text,
    retrieved_at double precision NOT NULL,
    source_url text NOT NULL,
    capture_sha256 character varying NOT NULL,
    content_sha256 character varying
);


--
-- Name: elections_results; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.elections_results (
    id bigint NOT NULL,
    report_id character varying NOT NULL,
    contest_id character varying NOT NULL,
    candidacy_id character varying,
    answer text,
    measure character varying NOT NULL,
    measure_as_shown text,
    polling_area_id character varying,
    unit_label_as_shown text,
    ballot_type character varying,
    ballot_type_as_shown text,
    round integer DEFAULT 1 NOT NULL,
    value bigint,
    reported_under text
);


--
-- Name: elections_results_id_seq; Type: SEQUENCE; Schema: fact_factory; Owner: -
--

CREATE SEQUENCE fact_factory.elections_results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: elections_results_id_seq; Type: SEQUENCE OWNED BY; Schema: fact_factory; Owner: -
--

ALTER SEQUENCE fact_factory.elections_results_id_seq OWNED BY fact_factory.elections_results.id;


--
-- Name: entities; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.entities (
    row_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    anchor character varying NOT NULL,
    entity_class character varying NOT NULL,
    subtype character varying,
    name text NOT NULL,
    name_fr text,
    aliases json NOT NULL,
    jurisdiction character varying,
    status character varying,
    valid_from character varying,
    valid_to character varying,
    attributes json NOT NULL,
    redirected_to character varying,
    content_sha256 character varying NOT NULL,
    source json NOT NULL,
    recorded_at double precision NOT NULL,
    revision_id integer NOT NULL,
    retired_revision_id integer
);


--
-- Name: entity_identifiers; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.entity_identifiers (
    row_id character varying NOT NULL,
    entity_id character varying NOT NULL,
    namespace character varying NOT NULL,
    value character varying NOT NULL,
    verified integer NOT NULL,
    vintage character varying,
    valid_from character varying,
    valid_to character varying,
    content_sha256 character varying NOT NULL,
    source json NOT NULL,
    recorded_at double precision NOT NULL,
    revision_id integer NOT NULL,
    retired_revision_id integer
);


--
-- Name: entity_names; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.entity_names (
    row_id character varying NOT NULL,
    kind character varying NOT NULL,
    name text NOT NULL,
    entity_id character varying NOT NULL,
    normalized_name text,
    match_key text,
    normalization character varying NOT NULL,
    revision_id integer NOT NULL,
    retired_revision_id integer
);


--
-- Name: entity_relationships; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.entity_relationships (
    row_id character varying NOT NULL,
    subject_id character varying NOT NULL,
    predicate character varying NOT NULL,
    object_id character varying,
    object_ref character varying,
    attributes json NOT NULL,
    valid_from character varying,
    valid_to character varying,
    content_sha256 character varying NOT NULL,
    source json NOT NULL,
    recorded_at double precision NOT NULL,
    revision_id integer NOT NULL,
    retired_revision_id integer
);


--
-- Name: entity_review_queue; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.entity_review_queue (
    id character varying NOT NULL,
    revision_id integer NOT NULL,
    entity_id character varying NOT NULL,
    reasons json NOT NULL,
    candidates json NOT NULL,
    survivor character varying,
    created_at double precision NOT NULL
);


--
-- Name: entity_tokens; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.entity_tokens (
    row_id character varying NOT NULL,
    token character varying NOT NULL,
    revision_id integer NOT NULL,
    token_count integer NOT NULL
);


--
-- Name: host_pacing; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.host_pacing (
    host character varying NOT NULL,
    interval_seconds double precision NOT NULL,
    max_running integer NOT NULL,
    next_at double precision NOT NULL,
    note text
);


--
-- Name: institutions; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.institutions (
    id character varying NOT NULL,
    province character varying,
    name text,
    website text,
    status character varying,
    metadata json NOT NULL
);


--
-- Name: mention_occurrences; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.mention_occurrences (
    row_id character varying NOT NULL,
    occurrence_id character varying NOT NULL,
    source_key character varying NOT NULL,
    snapshot_id character varying NOT NULL,
    spending_row_id character varying NOT NULL,
    field character varying NOT NULL,
    "position" integer NOT NULL,
    raw_name text,
    normalized_name text,
    province character varying,
    city text,
    postal_code character varying,
    fsa character varying,
    row_date character varying,
    fiscal_year integer,
    identifiers json NOT NULL,
    party_kind character varying NOT NULL,
    entity_id character varying,
    method character varying,
    reason character varying,
    candidates json,
    roster_refs json,
    rule_version character varying NOT NULL,
    row_context json,
    review_unit_id character varying,
    fuzzy_candidates json,
    kind_reason character varying,
    country character varying,
    create_unit text,
    create_reason character varying,
    evidence_sha256 character varying,
    content_sha256 character varying NOT NULL,
    source json NOT NULL,
    recorded_at double precision NOT NULL,
    revision_id integer NOT NULL,
    retired_revision_id integer
);


--
-- Name: mentions; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.mentions (
    id character varying NOT NULL,
    revision_id integer NOT NULL,
    source_key character varying NOT NULL,
    field character varying NOT NULL,
    raw_name text,
    normalized_name text,
    occurrences integer NOT NULL,
    linked integer NOT NULL,
    entity_ids json NOT NULL
);


--
-- Name: registry_revisions; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.registry_revisions (
    id integer NOT NULL,
    kind character varying NOT NULL,
    state character varying NOT NULL,
    reason text NOT NULL,
    inputs json NOT NULL,
    summary json,
    code_revision character varying,
    created_at double precision NOT NULL,
    committed_at double precision,
    pruned_at double precision,
    versions json
);


--
-- Name: registry_revisions_id_seq; Type: SEQUENCE; Schema: fact_factory; Owner: -
--

CREATE SEQUENCE fact_factory.registry_revisions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: registry_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: fact_factory; Owner: -
--

ALTER SEQUENCE fact_factory.registry_revisions_id_seq OWNED BY fact_factory.registry_revisions.id;


--
-- Name: registry_snapshots; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.registry_snapshots (
    name character varying NOT NULL,
    revision_id integer NOT NULL,
    reason text,
    held_by character varying,
    versions json,
    created_at double precision NOT NULL
);


--
-- Name: resolution_decisions; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.resolution_decisions (
    row_id character varying NOT NULL,
    decision_id character varying NOT NULL,
    subject character varying NOT NULL,
    subject_kind character varying NOT NULL,
    outcome character varying NOT NULL,
    entity_id character varying,
    entity_ref json,
    decider character varying NOT NULL,
    versions json NOT NULL,
    input_sha256 character varying,
    evidence json NOT NULL,
    supersedes character varying,
    retired_reason character varying,
    content_sha256 character varying NOT NULL,
    source json NOT NULL,
    recorded_at double precision NOT NULL,
    revision_id integer NOT NULL,
    retired_revision_id integer
);


--
-- Name: reviews; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.reviews (
    id character varying NOT NULL,
    kind character varying NOT NULL,
    subject character varying NOT NULL,
    document_id character varying,
    reason character varying,
    state character varying NOT NULL,
    evidence json NOT NULL,
    verdict character varying,
    survivor character varying,
    roster_ref character varying,
    note text,
    reviewed_by character varying,
    file_sha256 character varying,
    applied_revision_id integer,
    created_at double precision NOT NULL,
    updated_at double precision NOT NULL
);


--
-- Name: roster_capture_sets; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.roster_capture_sets (
    id character varying NOT NULL,
    source_key character varying NOT NULL,
    captures json NOT NULL,
    independent_count json,
    created_at double precision NOT NULL
);


--
-- Name: roster_captures; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.roster_captures (
    id character varying NOT NULL,
    source_key character varying NOT NULL,
    sha256 character varying NOT NULL,
    url text,
    retrieved_at double precision,
    row_count integer,
    metadata json NOT NULL,
    created_at double precision NOT NULL
);


--
-- Name: roster_index; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.roster_index (
    row_id character varying NOT NULL,
    capture_id character varying NOT NULL,
    source_key character varying NOT NULL,
    record_key character varying NOT NULL,
    bn9 character varying,
    normalized_name text,
    province character varying,
    status character varying
);


--
-- Name: roster_rows; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.roster_rows (
    id character varying NOT NULL,
    capture_id character varying NOT NULL,
    source_key character varying NOT NULL,
    row_number integer NOT NULL,
    record_key character varying NOT NULL,
    record json NOT NULL
);


--
-- Name: roster_tokens; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.roster_tokens (
    row_id character varying NOT NULL,
    token character varying NOT NULL,
    capture_id character varying NOT NULL,
    source_key character varying NOT NULL,
    record_key character varying NOT NULL,
    token_count integer NOT NULL
);


--
-- Name: spending_counterparties; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.spending_counterparties (
    id bigint NOT NULL,
    entity_id character varying NOT NULL,
    role character varying NOT NULL,
    counterparty_id character varying,
    asset_key character varying NOT NULL,
    source_key character varying NOT NULL,
    fiscal_year integer,
    currency character varying,
    measure character varying NOT NULL,
    record_count bigint NOT NULL,
    agreement_count bigint NOT NULL,
    amount numeric(38,6),
    amount_missing_count bigint NOT NULL,
    aggregated_excluded bigint NOT NULL,
    revisions_excluded bigint NOT NULL,
    revision_id integer NOT NULL,
    retired_revision_id integer
);


--
-- Name: spending_counterparties_id_seq; Type: SEQUENCE; Schema: fact_factory; Owner: -
--

ALTER TABLE fact_factory.spending_counterparties ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME fact_factory.spending_counterparties_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: spending_publications; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.spending_publications (
    id bigint NOT NULL,
    release_id character varying NOT NULL,
    source_key character varying NOT NULL,
    acquisition character varying NOT NULL,
    resource_id character varying NOT NULL,
    source_sha256 character varying NOT NULL,
    source_url text,
    parser_version character varying NOT NULL,
    observed_at double precision,
    row_count bigint,
    occurrence_copies bigint,
    content_copies bigint,
    duplicate_guard character varying,
    staged_at double precision NOT NULL,
    version bigint,
    committed_at double precision,
    replaced_version bigint,
    replaced_at double precision,
    purged_at double precision
);


--
-- Name: spending_publications_id_seq; Type: SEQUENCE; Schema: fact_factory; Owner: -
--

ALTER TABLE fact_factory.spending_publications ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME fact_factory.spending_publications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: spending_records; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.spending_records (
    publication_id bigint NOT NULL,
    row_number integer NOT NULL,
    id text,
    spending_key text,
    external_id text,
    canonical_id text,
    source_key text,
    acquisition text,
    resource_id text,
    source_url text,
    source_sha256 text,
    parser_version text,
    record_type text,
    title text,
    description text,
    payer text,
    payer_code text,
    recipient text,
    research_org text,
    recipient_business_number text,
    recipient_type text,
    recipient_city text,
    recipient_postal_code text,
    currency text,
    province text,
    country text,
    program text,
    principal_investigator text,
    date_raw text,
    raw_json text,
    raw_xml text,
    revision_rank_json text,
    commitments_json text,
    extra_json text,
    amount numeric(38,6),
    fiscal_year integer,
    source_occurrence bigint,
    is_aggregated boolean,
    value_consistent boolean,
    date date,
    recipients text[],
    recipient_refs text[]
);


--
-- Name: spending_snapshots; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.spending_snapshots (
    id character varying NOT NULL,
    source_key character varying,
    url text,
    sha256 character varying,
    normalized_sha256 character varying,
    publication json,
    row_count integer,
    parser_version character varying,
    metadata json NOT NULL,
    created_at double precision NOT NULL
);


--
-- Name: spending_summary; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.spending_summary (
    id bigint NOT NULL,
    entity_id character varying NOT NULL,
    role character varying NOT NULL,
    asset_key character varying NOT NULL,
    source_key character varying NOT NULL,
    fiscal_year integer,
    currency character varying,
    measure character varying NOT NULL,
    record_count bigint NOT NULL,
    agreement_count bigint NOT NULL,
    amount numeric(38,6),
    amount_missing_count bigint NOT NULL,
    aggregated_excluded bigint NOT NULL,
    revisions_excluded bigint NOT NULL,
    revision_id integer NOT NULL,
    retired_revision_id integer
);


--
-- Name: spending_summary_id_seq; Type: SEQUENCE; Schema: fact_factory; Owner: -
--

ALTER TABLE fact_factory.spending_summary ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME fact_factory.spending_summary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: statcan_captures; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.statcan_captures (
    id character varying NOT NULL,
    kind character varying NOT NULL,
    product_id bigint,
    day character varying,
    url text NOT NULL,
    sha256 character varying NOT NULL,
    bytes bigint NOT NULL,
    retrieved_at double precision NOT NULL,
    etag character varying,
    last_modified character varying,
    metadata json NOT NULL
);


--
-- Name: statcan_change_days; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.statcan_change_days (
    day character varying NOT NULL,
    capture_sha256 character varying,
    cubes integer,
    product_ids json,
    queued integer,
    fetched_at double precision NOT NULL
);


--
-- Name: statcan_cubes; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.statcan_cubes (
    product_id bigint NOT NULL,
    cansim_id character varying,
    title_en text,
    title_fr text,
    subject_codes json,
    survey_codes json,
    frequency_code integer,
    archived character varying,
    release_time double precision,
    cube_start_date character varying,
    cube_end_date character varying,
    issue_date character varying,
    corrections json,
    listing_sha256 character varying,
    first_listed_at double precision,
    listed_at double precision,
    delisted_at double precision,
    zip_bytes bigint,
    zip_checked_at double precision
);


--
-- Name: statcan_normalized; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.statcan_normalized (
    id character varying NOT NULL,
    product_id bigint NOT NULL,
    state character varying NOT NULL,
    attempt_key character varying NOT NULL,
    release_key character varying NOT NULL,
    normalizer_version character varying NOT NULL,
    registry_release_id integer,
    checks json NOT NULL,
    attempted_at double precision NOT NULL,
    published_key character varying,
    build_key character varying,
    raw_snapshot_id character varying,
    table_snapshot_id character varying,
    series_snapshot_id character varying,
    observations_snapshot_id character varying,
    rows bigint,
    series bigint,
    periods json,
    geo json,
    geo_stale boolean,
    registry_checked_release_id integer,
    published_at double precision
);


--
-- Name: statcan_releases; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.statcan_releases (
    id character varying NOT NULL,
    product_id bigint NOT NULL,
    state character varying NOT NULL,
    release_time double precision,
    csv_sha256 character varying NOT NULL,
    metadata_sha256 character varying NOT NULL,
    source_url text,
    retrieved_at double precision,
    parser_version character varying NOT NULL,
    layout character varying,
    rows bigint,
    checks json NOT NULL,
    publication json,
    metadata_published_at double precision,
    created_at double precision NOT NULL
);


--
-- Name: statcan_tables; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.statcan_tables (
    id character varying NOT NULL,
    product_id bigint NOT NULL,
    title_en text,
    title_fr text,
    subject_code character varying,
    frequency_code integer,
    archived character varying,
    release_time double precision,
    retrieved_at double precision,
    source_url text,
    table_url text,
    csv_sha256 character varying,
    metadata_sha256 character varying,
    layout character varying,
    rows bigint,
    snapshot_id character varying,
    metadata_location text,
    metadata_url text,
    parser_version character varying,
    release_key character varying,
    published_at double precision,
    licence character varying,
    delisted_at double precision
);


--
-- Name: token_frequencies; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.token_frequencies (
    revision_id integer NOT NULL,
    token character varying NOT NULL,
    frequency integer NOT NULL
);


--
-- Name: work; Type: TABLE; Schema: fact_factory; Owner: -
--

CREATE TABLE fact_factory.work (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    family character varying NOT NULL,
    key text NOT NULL,
    payload jsonb NOT NULL,
    state character varying NOT NULL,
    pool character varying NOT NULL,
    priority integer NOT NULL,
    host character varying,
    lane character varying,
    not_before double precision NOT NULL,
    attempts integer NOT NULL,
    max_attempts integer NOT NULL,
    lease_owner character varying,
    lease_until double precision,
    error text,
    result jsonb,
    created_at double precision NOT NULL,
    started_at double precision,
    finished_at double precision
);


--
-- Name: work_id_seq; Type: SEQUENCE; Schema: fact_factory; Owner: -
--

CREATE SEQUENCE fact_factory.work_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: work_id_seq; Type: SEQUENCE OWNED BY; Schema: fact_factory; Owner: -
--

ALTER SEQUENCE fact_factory.work_id_seq OWNED BY fact_factory.work.id;


--
-- Name: catalog_history id; Type: DEFAULT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.catalog_history ALTER COLUMN id SET DEFAULT nextval('fact_factory.catalog_history_id_seq'::regclass);


--
-- Name: elections_results id; Type: DEFAULT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_results ALTER COLUMN id SET DEFAULT nextval('fact_factory.elections_results_id_seq'::regclass);


--
-- Name: registry_revisions id; Type: DEFAULT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.registry_revisions ALTER COLUMN id SET DEFAULT nextval('fact_factory.registry_revisions_id_seq'::regclass);


--
-- Name: work id; Type: DEFAULT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.work ALTER COLUMN id SET DEFAULT nextval('fact_factory.work_id_seq'::regclass);


--
-- Name: ai_review_answers ai_review_answers_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.ai_review_answers
    ADD CONSTRAINT ai_review_answers_pkey PRIMARY KEY (pair_sha256, unit_id);


--
-- Name: ai_review_units ai_review_units_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.ai_review_units
    ADD CONSTRAINT ai_review_units_pkey PRIMARY KEY (unit_id);


--
-- Name: ai_spend ai_spend_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.ai_spend
    ADD CONSTRAINT ai_spend_pkey PRIMARY KEY (run_id);


--
-- Name: artifacts artifacts_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.artifacts
    ADD CONSTRAINT artifacts_pkey PRIMARY KEY (sha256);


--
-- Name: catalog_history catalog_history_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.catalog_history
    ADD CONSTRAINT catalog_history_pkey PRIMARY KEY (id);


--
-- Name: corporation_detail_archives corporation_detail_archives_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.corporation_detail_archives
    ADD CONSTRAINT corporation_detail_archives_pkey PRIMARY KEY (sha256);


--
-- Name: corporation_detail_plan corporation_detail_plan_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.corporation_detail_plan
    ADD CONSTRAINT corporation_detail_plan_pkey PRIMARY KEY (corporation_number);


--
-- Name: corporation_details corporation_details_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.corporation_details
    ADD CONSTRAINT corporation_details_pkey PRIMARY KEY (corporation_number);


--
-- Name: corporation_directors corporation_directors_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.corporation_directors
    ADD CONSTRAINT corporation_directors_pkey PRIMARY KEY (corporation_number, "position");


--
-- Name: corporation_pages corporation_pages_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.corporation_pages
    ADD CONSTRAINT corporation_pages_pkey PRIMARY KEY (corporation_number);


--
-- Name: corporation_significant_control corporation_significant_control_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.corporation_significant_control
    ADD CONSTRAINT corporation_significant_control_pkey PRIMARY KEY (corporation_number, "position");


--
-- Name: derived_builds derived_builds_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.derived_builds
    ADD CONSTRAINT derived_builds_pkey PRIMARY KEY (revision_id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: elections_boundary_sets elections_boundary_sets_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_boundary_sets
    ADD CONSTRAINT elections_boundary_sets_pkey PRIMARY KEY (id);


--
-- Name: elections_candidacies elections_candidacies_contest_id_normalized_name_key; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_candidacies
    ADD CONSTRAINT elections_candidacies_contest_id_normalized_name_key UNIQUE (contest_id, normalized_name);


--
-- Name: elections_candidacies elections_candidacies_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_candidacies
    ADD CONSTRAINT elections_candidacies_pkey PRIMARY KEY (id);


--
-- Name: elections_candidate_contacts elections_candidate_contacts_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_candidate_contacts
    ADD CONSTRAINT elections_candidate_contacts_pkey PRIMARY KEY (candidacy_id, kind, platform, value);


--
-- Name: elections_captures elections_captures_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_captures
    ADD CONSTRAINT elections_captures_pkey PRIMARY KEY (sha256);


--
-- Name: elections_contact_research elections_contact_research_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_contact_research
    ADD CONSTRAINT elections_contact_research_pkey PRIMARY KEY (pair_sha256, candidacy_id);


--
-- Name: elections_contests elections_contests_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_contests
    ADD CONSTRAINT elections_contests_pkey PRIMARY KEY (id);


--
-- Name: elections_districts elections_districts_boundary_set_id_code_key; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_districts
    ADD CONSTRAINT elections_districts_boundary_set_id_code_key UNIQUE (boundary_set_id, code);


--
-- Name: elections_districts elections_districts_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_districts
    ADD CONSTRAINT elections_districts_pkey PRIMARY KEY (id);


--
-- Name: elections_elections elections_elections_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_elections
    ADD CONSTRAINT elections_elections_pkey PRIMARY KEY (id);


--
-- Name: elections_offices elections_offices_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_offices
    ADD CONSTRAINT elections_offices_pkey PRIMARY KEY (id);


--
-- Name: elections_polling_areas elections_polling_areas_boundary_set_id_district_id_code_key; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_polling_areas
    ADD CONSTRAINT elections_polling_areas_boundary_set_id_district_id_code_key UNIQUE (boundary_set_id, district_id, code);


--
-- Name: elections_polling_areas elections_polling_areas_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_polling_areas
    ADD CONSTRAINT elections_polling_areas_pkey PRIMARY KEY (id);


--
-- Name: elections_result_reports elections_result_reports_capture_sha256_key; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_result_reports
    ADD CONSTRAINT elections_result_reports_capture_sha256_key UNIQUE (capture_sha256);


--
-- Name: elections_result_reports elections_result_reports_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_result_reports
    ADD CONSTRAINT elections_result_reports_pkey PRIMARY KEY (id);


--
-- Name: elections_results elections_results_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_results
    ADD CONSTRAINT elections_results_pkey PRIMARY KEY (id);


--
-- Name: entities entities_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.entities
    ADD CONSTRAINT entities_pkey PRIMARY KEY (row_id);


--
-- Name: entity_identifiers entity_identifiers_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.entity_identifiers
    ADD CONSTRAINT entity_identifiers_pkey PRIMARY KEY (row_id);


--
-- Name: entity_names entity_names_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.entity_names
    ADD CONSTRAINT entity_names_pkey PRIMARY KEY (row_id, kind, name);


--
-- Name: entity_relationships entity_relationships_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.entity_relationships
    ADD CONSTRAINT entity_relationships_pkey PRIMARY KEY (row_id);


--
-- Name: entity_review_queue entity_review_queue_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.entity_review_queue
    ADD CONSTRAINT entity_review_queue_pkey PRIMARY KEY (id);


--
-- Name: entity_tokens entity_tokens_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.entity_tokens
    ADD CONSTRAINT entity_tokens_pkey PRIMARY KEY (row_id, token);


--
-- Name: host_pacing host_pacing_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.host_pacing
    ADD CONSTRAINT host_pacing_pkey PRIMARY KEY (host);


--
-- Name: institutions institutions_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.institutions
    ADD CONSTRAINT institutions_pkey PRIMARY KEY (id);


--
-- Name: mention_occurrences mention_occurrences_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.mention_occurrences
    ADD CONSTRAINT mention_occurrences_pkey PRIMARY KEY (row_id);


--
-- Name: mentions mentions_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.mentions
    ADD CONSTRAINT mentions_pkey PRIMARY KEY (id);


--
-- Name: registry_revisions registry_revisions_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.registry_revisions
    ADD CONSTRAINT registry_revisions_pkey PRIMARY KEY (id);


--
-- Name: registry_snapshots registry_snapshots_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.registry_snapshots
    ADD CONSTRAINT registry_snapshots_pkey PRIMARY KEY (name);


--
-- Name: resolution_decisions resolution_decisions_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.resolution_decisions
    ADD CONSTRAINT resolution_decisions_pkey PRIMARY KEY (row_id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: roster_capture_sets roster_capture_sets_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.roster_capture_sets
    ADD CONSTRAINT roster_capture_sets_pkey PRIMARY KEY (id);


--
-- Name: roster_captures roster_captures_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.roster_captures
    ADD CONSTRAINT roster_captures_pkey PRIMARY KEY (id);


--
-- Name: roster_index roster_index_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.roster_index
    ADD CONSTRAINT roster_index_pkey PRIMARY KEY (row_id);


--
-- Name: roster_rows roster_row_location; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.roster_rows
    ADD CONSTRAINT roster_row_location UNIQUE (capture_id, row_number);


--
-- Name: roster_rows roster_rows_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.roster_rows
    ADD CONSTRAINT roster_rows_pkey PRIMARY KEY (id);


--
-- Name: roster_tokens roster_tokens_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.roster_tokens
    ADD CONSTRAINT roster_tokens_pkey PRIMARY KEY (row_id, token);


--
-- Name: spending_counterparties spending_counterparties_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.spending_counterparties
    ADD CONSTRAINT spending_counterparties_pkey PRIMARY KEY (id);


--
-- Name: spending_publications spending_publications_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.spending_publications
    ADD CONSTRAINT spending_publications_pkey PRIMARY KEY (id);


--
-- Name: spending_publications spending_publications_version_key; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.spending_publications
    ADD CONSTRAINT spending_publications_version_key UNIQUE (version);


--
-- Name: spending_records spending_records_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.spending_records
    ADD CONSTRAINT spending_records_pkey PRIMARY KEY (publication_id, row_number);


--
-- Name: spending_snapshots spending_snapshots_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.spending_snapshots
    ADD CONSTRAINT spending_snapshots_pkey PRIMARY KEY (id);


--
-- Name: spending_summary spending_summary_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.spending_summary
    ADD CONSTRAINT spending_summary_pkey PRIMARY KEY (id);


--
-- Name: statcan_captures statcan_captures_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.statcan_captures
    ADD CONSTRAINT statcan_captures_pkey PRIMARY KEY (id);


--
-- Name: statcan_change_days statcan_change_days_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.statcan_change_days
    ADD CONSTRAINT statcan_change_days_pkey PRIMARY KEY (day);


--
-- Name: statcan_cubes statcan_cubes_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.statcan_cubes
    ADD CONSTRAINT statcan_cubes_pkey PRIMARY KEY (product_id);


--
-- Name: statcan_normalized statcan_normalized_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.statcan_normalized
    ADD CONSTRAINT statcan_normalized_pkey PRIMARY KEY (id);


--
-- Name: statcan_normalized statcan_normalized_product_id_key; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.statcan_normalized
    ADD CONSTRAINT statcan_normalized_product_id_key UNIQUE (product_id);


--
-- Name: statcan_releases statcan_releases_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.statcan_releases
    ADD CONSTRAINT statcan_releases_pkey PRIMARY KEY (id);


--
-- Name: statcan_tables statcan_tables_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.statcan_tables
    ADD CONSTRAINT statcan_tables_pkey PRIMARY KEY (id);


--
-- Name: statcan_tables statcan_tables_product_id_key; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.statcan_tables
    ADD CONSTRAINT statcan_tables_product_id_key UNIQUE (product_id);


--
-- Name: token_frequencies token_frequencies_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.token_frequencies
    ADD CONSTRAINT token_frequencies_pkey PRIMARY KEY (revision_id, token);


--
-- Name: work work_identity; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.work
    ADD CONSTRAINT work_identity UNIQUE (kind, key);


--
-- Name: work work_pkey; Type: CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.work
    ADD CONSTRAINT work_pkey PRIMARY KEY (id);


--
-- Name: document_institution_bytes; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE UNIQUE INDEX document_institution_bytes ON fact_factory.documents USING btree (institution_id, sha256);


--
-- Name: ix_ai_review_answers_run_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_ai_review_answers_run_id ON fact_factory.ai_review_answers USING btree (run_id);


--
-- Name: ix_ai_spend_state; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_ai_spend_state ON fact_factory.ai_spend USING btree (state);


--
-- Name: ix_catalog_history_visible_from; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_catalog_history_visible_from ON fact_factory.catalog_history USING btree (visible_from);


--
-- Name: ix_corporation_detail_archives_shard; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_detail_archives_shard ON fact_factory.corporation_detail_archives USING btree (shard);


--
-- Name: ix_corporation_detail_plan_shard; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_detail_plan_shard ON fact_factory.corporation_detail_plan USING btree (shard);


--
-- Name: ix_corporation_details_archive_sha256; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_details_archive_sha256 ON fact_factory.corporation_details USING btree (archive_sha256);


--
-- Name: ix_corporation_details_bn9; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_details_bn9 ON fact_factory.corporation_details USING btree (bn9);


--
-- Name: ix_corporation_details_outcome; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_details_outcome ON fact_factory.corporation_details USING btree (outcome);


--
-- Name: ix_corporation_details_status; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_details_status ON fact_factory.corporation_details USING btree (status);


--
-- Name: ix_corporation_directors_name; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_directors_name ON fact_factory.corporation_directors USING btree (name);


--
-- Name: ix_corporation_pages_archive_sha256; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_pages_archive_sha256 ON fact_factory.corporation_pages USING btree (archive_sha256);


--
-- Name: ix_corporation_pages_outcome; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_pages_outcome ON fact_factory.corporation_pages USING btree (outcome);


--
-- Name: ix_corporation_significant_control_name; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_corporation_significant_control_name ON fact_factory.corporation_significant_control USING btree (name);


--
-- Name: ix_documents_acquisition; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_documents_acquisition ON fact_factory.documents USING btree (acquisition);


--
-- Name: ix_documents_institution_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_documents_institution_id ON fact_factory.documents USING btree (institution_id);


--
-- Name: ix_documents_sha256; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_documents_sha256 ON fact_factory.documents USING btree (sha256);


--
-- Name: ix_documents_source_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_documents_source_key ON fact_factory.documents USING btree (source_key);


--
-- Name: ix_documents_state; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_documents_state ON fact_factory.documents USING btree (state);


--
-- Name: ix_elections_captures_kind; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_elections_captures_kind ON fact_factory.elections_captures USING btree (kind);


--
-- Name: ix_elections_contact_research_run_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_elections_contact_research_run_id ON fact_factory.elections_contact_research USING btree (run_id);


--
-- Name: ix_elections_districts_geometry; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_elections_districts_geometry ON fact_factory.elections_districts USING gist (geometry);


--
-- Name: ix_elections_elections_jurisdiction; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_elections_elections_jurisdiction ON fact_factory.elections_elections USING btree (jurisdiction);


--
-- Name: ix_elections_polling_areas_geometry; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_elections_polling_areas_geometry ON fact_factory.elections_polling_areas USING gist (geometry);


--
-- Name: ix_elections_results_contest_report; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_elections_results_contest_report ON fact_factory.elections_results USING btree (contest_id, report_id);


--
-- Name: ix_entities_anchor; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entities_anchor ON fact_factory.entities USING btree (anchor);


--
-- Name: ix_entities_entity_class; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entities_entity_class ON fact_factory.entities USING btree (entity_class);


--
-- Name: ix_entities_entity_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entities_entity_id ON fact_factory.entities USING btree (entity_id);


--
-- Name: ix_entities_jurisdiction; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entities_jurisdiction ON fact_factory.entities USING btree (jurisdiction);


--
-- Name: ix_entities_name; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entities_name ON fact_factory.entities USING btree (name, entity_id);


--
-- Name: ix_entities_retired_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entities_retired_revision_id ON fact_factory.entities USING btree (retired_revision_id);


--
-- Name: ix_entities_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entities_revision_id ON fact_factory.entities USING btree (revision_id);


--
-- Name: ix_entity_identifiers_entity_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_identifiers_entity_id ON fact_factory.entity_identifiers USING btree (entity_id);


--
-- Name: ix_entity_identifiers_namespace; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_identifiers_namespace ON fact_factory.entity_identifiers USING btree (namespace);


--
-- Name: ix_entity_identifiers_retired_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_identifiers_retired_revision_id ON fact_factory.entity_identifiers USING btree (retired_revision_id);


--
-- Name: ix_entity_identifiers_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_identifiers_revision_id ON fact_factory.entity_identifiers USING btree (revision_id);


--
-- Name: ix_entity_identifiers_value; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_identifiers_value ON fact_factory.entity_identifiers USING btree (value);


--
-- Name: ix_entity_names_entity_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_names_entity_id ON fact_factory.entity_names USING btree (entity_id);


--
-- Name: ix_entity_names_match_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_names_match_key ON fact_factory.entity_names USING btree (match_key);


--
-- Name: ix_entity_names_retired; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_names_retired ON fact_factory.entity_names USING btree (retired_revision_id) WHERE (retired_revision_id IS NOT NULL);


--
-- Name: ix_entity_names_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_names_revision_id ON fact_factory.entity_names USING btree (revision_id);


--
-- Name: ix_entity_relationships_object_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_relationships_object_id ON fact_factory.entity_relationships USING btree (object_id);


--
-- Name: ix_entity_relationships_predicate; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_relationships_predicate ON fact_factory.entity_relationships USING btree (predicate);


--
-- Name: ix_entity_relationships_retired_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_relationships_retired_revision_id ON fact_factory.entity_relationships USING btree (retired_revision_id);


--
-- Name: ix_entity_relationships_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_relationships_revision_id ON fact_factory.entity_relationships USING btree (revision_id);


--
-- Name: ix_entity_relationships_subject_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_relationships_subject_id ON fact_factory.entity_relationships USING btree (subject_id);


--
-- Name: ix_entity_review_queue_entity_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_review_queue_entity_id ON fact_factory.entity_review_queue USING btree (entity_id);


--
-- Name: ix_entity_review_queue_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_review_queue_revision_id ON fact_factory.entity_review_queue USING btree (revision_id);


--
-- Name: ix_entity_tokens_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_tokens_revision_id ON fact_factory.entity_tokens USING btree (revision_id);


--
-- Name: ix_entity_tokens_token; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_entity_tokens_token ON fact_factory.entity_tokens USING btree (token);


--
-- Name: ix_institutions_province; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_institutions_province ON fact_factory.institutions USING btree (province);


--
-- Name: ix_mention_occurrences_create_reason; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_create_reason ON fact_factory.mention_occurrences USING btree (create_reason);


--
-- Name: ix_mention_occurrences_create_unit; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_create_unit ON fact_factory.mention_occurrences USING btree (create_unit);


--
-- Name: ix_mention_occurrences_entity_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_entity_id ON fact_factory.mention_occurrences USING btree (entity_id);


--
-- Name: ix_mention_occurrences_id_current; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_id_current ON fact_factory.mention_occurrences USING btree (occurrence_id, retired_revision_id);


--
-- Name: ix_mention_occurrences_normalized_name; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_normalized_name ON fact_factory.mention_occurrences USING btree (normalized_name);


--
-- Name: ix_mention_occurrences_reason; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_reason ON fact_factory.mention_occurrences USING btree (reason);


--
-- Name: ix_mention_occurrences_retired; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_retired ON fact_factory.mention_occurrences USING btree (retired_revision_id) WHERE (retired_revision_id IS NOT NULL);


--
-- Name: ix_mention_occurrences_review_unit_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_review_unit_id ON fact_factory.mention_occurrences USING btree (review_unit_id);


--
-- Name: ix_mention_occurrences_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_revision_id ON fact_factory.mention_occurrences USING btree (revision_id);


--
-- Name: ix_mention_occurrences_source_current; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_source_current ON fact_factory.mention_occurrences USING btree (source_key, retired_revision_id, occurrence_id, row_id);


--
-- Name: ix_mention_occurrences_source_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_source_key ON fact_factory.mention_occurrences USING btree (source_key);


--
-- Name: ix_mention_occurrences_spending_row; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mention_occurrences_spending_row ON fact_factory.mention_occurrences USING btree (source_key, spending_row_id);


--
-- Name: ix_mentions_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_mentions_revision_id ON fact_factory.mentions USING btree (revision_id);


--
-- Name: ix_registry_revisions_state; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_registry_revisions_state ON fact_factory.registry_revisions USING btree (state);


--
-- Name: ix_registry_snapshots_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_registry_snapshots_revision_id ON fact_factory.registry_snapshots USING btree (revision_id);


--
-- Name: ix_resolution_decisions_decision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_resolution_decisions_decision_id ON fact_factory.resolution_decisions USING btree (decision_id);


--
-- Name: ix_resolution_decisions_retired; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_resolution_decisions_retired ON fact_factory.resolution_decisions USING btree (retired_revision_id) WHERE (retired_revision_id IS NOT NULL);


--
-- Name: ix_resolution_decisions_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_resolution_decisions_revision_id ON fact_factory.resolution_decisions USING btree (revision_id);


--
-- Name: ix_resolution_decisions_subject; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_resolution_decisions_subject ON fact_factory.resolution_decisions USING btree (subject);


--
-- Name: ix_reviews_document_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_reviews_document_id ON fact_factory.reviews USING btree (document_id);


--
-- Name: ix_reviews_kind; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_reviews_kind ON fact_factory.reviews USING btree (kind);


--
-- Name: ix_reviews_reason; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_reviews_reason ON fact_factory.reviews USING btree (reason);


--
-- Name: ix_reviews_state; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_reviews_state ON fact_factory.reviews USING btree (state);


--
-- Name: ix_reviews_subject; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_reviews_subject ON fact_factory.reviews USING btree (subject);


--
-- Name: ix_roster_capture_sets_source_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_capture_sets_source_key ON fact_factory.roster_capture_sets USING btree (source_key);


--
-- Name: ix_roster_captures_source_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_captures_source_key ON fact_factory.roster_captures USING btree (source_key);


--
-- Name: ix_roster_index_bn9_source; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_index_bn9_source ON fact_factory.roster_index USING btree (bn9, source_key);


--
-- Name: ix_roster_index_capture_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_index_capture_id ON fact_factory.roster_index USING btree (capture_id);


--
-- Name: ix_roster_index_name_source; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_index_name_source ON fact_factory.roster_index USING btree (normalized_name, source_key);


--
-- Name: ix_roster_index_record_source; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_index_record_source ON fact_factory.roster_index USING btree (record_key, source_key);


--
-- Name: ix_roster_index_source_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_index_source_key ON fact_factory.roster_index USING btree (source_key);


--
-- Name: ix_roster_rows_capture_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_rows_capture_id ON fact_factory.roster_rows USING btree (capture_id);


--
-- Name: ix_roster_rows_capture_record; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_rows_capture_record ON fact_factory.roster_rows USING btree (capture_id, record_key);


--
-- Name: ix_roster_rows_source_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_rows_source_key ON fact_factory.roster_rows USING btree (source_key);


--
-- Name: ix_roster_tokens_capture_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_tokens_capture_id ON fact_factory.roster_tokens USING btree (capture_id);


--
-- Name: ix_roster_tokens_postings; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_tokens_postings ON fact_factory.roster_tokens USING btree (token, capture_id, token_count, row_id);


--
-- Name: ix_roster_tokens_source_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_roster_tokens_source_key ON fact_factory.roster_tokens USING btree (source_key);


--
-- Name: ix_spending_counterparties_entity; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_counterparties_entity ON fact_factory.spending_counterparties USING btree (entity_id, revision_id);


--
-- Name: ix_spending_counterparties_retired; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_counterparties_retired ON fact_factory.spending_counterparties USING btree (retired_revision_id) WHERE (retired_revision_id IS NOT NULL);


--
-- Name: ix_spending_counterparties_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_counterparties_revision_id ON fact_factory.spending_counterparties USING btree (revision_id);


--
-- Name: ix_spending_publications_current; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE UNIQUE INDEX ix_spending_publications_current ON fact_factory.spending_publications USING btree (source_key, acquisition, resource_id) WHERE ((version IS NOT NULL) AND (replaced_version IS NULL));


--
-- Name: ix_spending_publications_release; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_publications_release ON fact_factory.spending_publications USING btree (release_id);


--
-- Name: ix_spending_publications_resource; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_publications_resource ON fact_factory.spending_publications USING btree (source_key, acquisition, resource_id);


--
-- Name: ix_spending_records_amount; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_records_amount ON fact_factory.spending_records USING btree (amount DESC NULLS LAST, spending_key);


--
-- Name: ix_spending_records_canonical; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_records_canonical ON fact_factory.spending_records USING btree (canonical_id);


--
-- Name: ix_spending_records_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_records_id ON fact_factory.spending_records USING btree (id);


--
-- Name: ix_spending_records_payer; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_records_payer ON fact_factory.spending_records USING btree (payer_code, fiscal_year);


--
-- Name: ix_spending_records_repeated; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_records_repeated ON fact_factory.spending_records USING btree (publication_id, external_id) WHERE (source_occurrence > 1);


--
-- Name: ix_spending_records_spending_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_records_spending_key ON fact_factory.spending_records USING btree (spending_key);


--
-- Name: ix_spending_snapshots_source_key; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_snapshots_source_key ON fact_factory.spending_snapshots USING btree (source_key);


--
-- Name: ix_spending_summary_entity; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_summary_entity ON fact_factory.spending_summary USING btree (entity_id, revision_id);


--
-- Name: ix_spending_summary_retired; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_summary_retired ON fact_factory.spending_summary USING btree (retired_revision_id) WHERE (retired_revision_id IS NOT NULL);


--
-- Name: ix_spending_summary_revision_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_spending_summary_revision_id ON fact_factory.spending_summary USING btree (revision_id);


--
-- Name: ix_statcan_captures_kind; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_statcan_captures_kind ON fact_factory.statcan_captures USING btree (kind);


--
-- Name: ix_statcan_captures_product_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_statcan_captures_product_id ON fact_factory.statcan_captures USING btree (product_id);


--
-- Name: ix_statcan_captures_sha256; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_statcan_captures_sha256 ON fact_factory.statcan_captures USING btree (sha256);


--
-- Name: ix_statcan_releases_product_id; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_statcan_releases_product_id ON fact_factory.statcan_releases USING btree (product_id);


--
-- Name: ix_work_family_state; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_work_family_state ON fact_factory.work USING btree (family, kind, state);


--
-- Name: ix_work_lane; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_work_lane ON fact_factory.work USING btree (lane);


--
-- Name: ix_work_ready; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_work_ready ON fact_factory.work USING btree (pool, priority, not_before) WHERE ((state)::text = 'ready'::text);


--
-- Name: ix_work_running; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE INDEX ix_work_running ON fact_factory.work USING btree (lease_until) WHERE ((state)::text = 'running'::text);


--
-- Name: uq_registry_revisions_one_open; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE UNIQUE INDEX uq_registry_revisions_one_open ON fact_factory.registry_revisions USING btree (state) WHERE ((state)::text = 'open'::text);


--
-- Name: uq_work_running_lane; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE UNIQUE INDEX uq_work_running_lane ON fact_factory.work USING btree (lane) WHERE (((state)::text = 'running'::text) AND (lane IS NOT NULL));


--
-- Name: ux_elections_contests_office_district; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE UNIQUE INDEX ux_elections_contests_office_district ON fact_factory.elections_contests USING btree (election_id, office_id, district_id);


--
-- Name: ux_elections_contests_question; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE UNIQUE INDEX ux_elections_contests_question ON fact_factory.elections_contests USING btree (election_id, question_number);


--
-- Name: ux_elections_results_count; Type: INDEX; Schema: fact_factory; Owner: -
--

CREATE UNIQUE INDEX ux_elections_results_count ON fact_factory.elections_results USING btree (report_id, contest_id, COALESCE(candidacy_id, ''::character varying), COALESCE(answer, ''::text), COALESCE(polling_area_id, ''::character varying), COALESCE(unit_label_as_shown, ''::text), COALESCE(ballot_type_as_shown, ''::text), round, measure);


--
-- Name: elections_boundary_sets elections_boundary_sets_district_set_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_boundary_sets
    ADD CONSTRAINT elections_boundary_sets_district_set_id_fkey FOREIGN KEY (district_set_id) REFERENCES fact_factory.elections_boundary_sets(id);


--
-- Name: elections_candidacies elections_candidacies_contest_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_candidacies
    ADD CONSTRAINT elections_candidacies_contest_id_fkey FOREIGN KEY (contest_id) REFERENCES fact_factory.elections_contests(id);


--
-- Name: elections_candidate_contacts elections_candidate_contacts_candidacy_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_candidate_contacts
    ADD CONSTRAINT elections_candidate_contacts_candidacy_id_fkey FOREIGN KEY (candidacy_id) REFERENCES fact_factory.elections_candidacies(id);


--
-- Name: elections_contact_research elections_contact_research_candidacy_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_contact_research
    ADD CONSTRAINT elections_contact_research_candidacy_id_fkey FOREIGN KEY (candidacy_id) REFERENCES fact_factory.elections_candidacies(id);


--
-- Name: elections_contests elections_contests_district_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_contests
    ADD CONSTRAINT elections_contests_district_id_fkey FOREIGN KEY (district_id) REFERENCES fact_factory.elections_districts(id);


--
-- Name: elections_contests elections_contests_election_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_contests
    ADD CONSTRAINT elections_contests_election_id_fkey FOREIGN KEY (election_id) REFERENCES fact_factory.elections_elections(id);


--
-- Name: elections_contests elections_contests_office_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_contests
    ADD CONSTRAINT elections_contests_office_id_fkey FOREIGN KEY (office_id) REFERENCES fact_factory.elections_offices(id);


--
-- Name: elections_districts elections_districts_boundary_set_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_districts
    ADD CONSTRAINT elections_districts_boundary_set_id_fkey FOREIGN KEY (boundary_set_id) REFERENCES fact_factory.elections_boundary_sets(id);


--
-- Name: elections_polling_areas elections_polling_areas_boundary_set_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_polling_areas
    ADD CONSTRAINT elections_polling_areas_boundary_set_id_fkey FOREIGN KEY (boundary_set_id) REFERENCES fact_factory.elections_boundary_sets(id);


--
-- Name: elections_polling_areas elections_polling_areas_district_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_polling_areas
    ADD CONSTRAINT elections_polling_areas_district_id_fkey FOREIGN KEY (district_id) REFERENCES fact_factory.elections_districts(id);


--
-- Name: elections_polling_areas elections_polling_areas_parent_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_polling_areas
    ADD CONSTRAINT elections_polling_areas_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES fact_factory.elections_polling_areas(id);


--
-- Name: elections_result_reports elections_result_reports_election_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_result_reports
    ADD CONSTRAINT elections_result_reports_election_id_fkey FOREIGN KEY (election_id) REFERENCES fact_factory.elections_elections(id);


--
-- Name: elections_results elections_results_candidacy_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_results
    ADD CONSTRAINT elections_results_candidacy_id_fkey FOREIGN KEY (candidacy_id) REFERENCES fact_factory.elections_candidacies(id);


--
-- Name: elections_results elections_results_contest_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_results
    ADD CONSTRAINT elections_results_contest_id_fkey FOREIGN KEY (contest_id) REFERENCES fact_factory.elections_contests(id);


--
-- Name: elections_results elections_results_polling_area_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_results
    ADD CONSTRAINT elections_results_polling_area_id_fkey FOREIGN KEY (polling_area_id) REFERENCES fact_factory.elections_polling_areas(id);


--
-- Name: elections_results elections_results_report_id_fkey; Type: FK CONSTRAINT; Schema: fact_factory; Owner: -
--

ALTER TABLE ONLY fact_factory.elections_results
    ADD CONSTRAINT elections_results_report_id_fkey FOREIGN KEY (report_id) REFERENCES fact_factory.elections_result_reports(id);


--
-- PostgreSQL database dump complete
--

