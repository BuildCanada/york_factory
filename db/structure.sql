SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: warehouse; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS warehouse;


CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    record_id bigint NOT NULL,
    record_type character varying NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    content_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    filename character varying NOT NULL,
    key character varying NOT NULL,
    metadata text,
    service_name character varying NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: builders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.builders (
    id bigint NOT NULL,
    byline_en text,
    byline_fr text,
    created_at timestamp(6) without time zone NOT NULL,
    published_at timestamp(6) without time zone,
    quote_en text,
    quote_fr text,
    slug character varying NOT NULL,
    title_en character varying,
    title_fr character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    body_md_en text,
    body_md_fr text,
    author_md_en text,
    author_md_fr text
);


--
-- Name: builders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.builders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: builders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.builders_id_seq OWNED BY public.builders.id;


--
-- Name: faqs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.faqs (
    id bigint NOT NULL,
    answer_text_en text,
    answer_text_fr text,
    created_at timestamp(6) without time zone NOT NULL,
    link_href character varying,
    link_text character varying,
    "position" integer DEFAULT 0,
    published_at timestamp(6) without time zone,
    question_en text,
    question_fr text,
    updated_at timestamp(6) without time zone NOT NULL,
    answer_md_en text,
    answer_md_fr text
);


--
-- Name: faqs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.faqs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: faqs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.faqs_id_seq OWNED BY public.faqs.id;


--
-- Name: feed_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feed_entries (
    id bigint NOT NULL,
    feedable_type character varying NOT NULL,
    feedable_id bigint NOT NULL,
    published_at timestamp(6) without time zone NOT NULL,
    featured boolean DEFAULT false,
    tags character varying[] DEFAULT '{}'::character varying[],
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: feed_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.feed_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feed_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.feed_entries_id_seq OWNED BY public.feed_entries.id;


--
-- Name: friendly_id_slugs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.friendly_id_slugs (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone,
    scope character varying,
    slug character varying NOT NULL,
    sluggable_id integer NOT NULL,
    sluggable_type character varying(50)
);


--
-- Name: friendly_id_slugs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.friendly_id_slugs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: friendly_id_slugs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.friendly_id_slugs_id_seq OWNED BY public.friendly_id_slugs.id;


--
-- Name: jwt_denylists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jwt_denylists (
    id bigint NOT NULL,
    exp timestamp(6) without time zone NOT NULL,
    jti character varying NOT NULL
);


--
-- Name: jwt_denylists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jwt_denylists_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jwt_denylists_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jwt_denylists_id_seq OWNED BY public.jwt_denylists.id;


--
-- Name: memos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memos (
    id bigint NOT NULL,
    author_avatar character varying,
    author_id bigint,
    author_name character varying,
    author_title character varying,
    category character varying,
    co_author_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    featured boolean DEFAULT false,
    key_messages_en jsonb DEFAULT '[]'::jsonb,
    key_messages_fr jsonb DEFAULT '[]'::jsonb,
    published_at timestamp(6) without time zone,
    slug character varying NOT NULL,
    title_en character varying,
    title_fr character varying,
    twitter_embed text,
    updated_at timestamp(6) without time zone NOT NULL,
    body_md_en text,
    body_md_fr text,
    appendix_md_en text,
    appendix_md_fr text,
    supporters_md_en text,
    supporters_md_fr text,
    publication character varying
);


--
-- Name: memos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.memos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: memos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.memos_id_seq OWNED BY public.memos.id;


--
-- Name: metrics_linkedin_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_linkedin_stats (
    id bigint NOT NULL,
    date date NOT NULL,
    impressions_organic integer DEFAULT 0 NOT NULL,
    impressions_sponsored integer DEFAULT 0 NOT NULL,
    impressions_total integer DEFAULT 0 NOT NULL,
    unique_impressions_organic integer DEFAULT 0 NOT NULL,
    clicks_organic integer DEFAULT 0 NOT NULL,
    clicks_sponsored integer DEFAULT 0 NOT NULL,
    clicks_total integer DEFAULT 0 NOT NULL,
    reactions_organic integer DEFAULT 0 NOT NULL,
    reactions_sponsored integer DEFAULT 0 NOT NULL,
    reactions_total integer DEFAULT 0 NOT NULL,
    comments_organic integer DEFAULT 0 NOT NULL,
    comments_sponsored integer DEFAULT 0 NOT NULL,
    comments_total integer DEFAULT 0 NOT NULL,
    reposts_organic integer DEFAULT 0 NOT NULL,
    reposts_sponsored integer DEFAULT 0 NOT NULL,
    reposts_total integer DEFAULT 0 NOT NULL,
    engagement_rate_organic numeric(8,6),
    engagement_rate_sponsored numeric(8,6),
    engagement_rate_total numeric(8,6),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    account character varying DEFAULT 'build_canada'::character varying NOT NULL
);


--
-- Name: metrics_linkedin_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_linkedin_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_linkedin_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_linkedin_stats_id_seq OWNED BY public.metrics_linkedin_stats.id;


--
-- Name: metrics_substack_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_substack_stats (
    id bigint NOT NULL,
    date date NOT NULL,
    views integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    account character varying DEFAULT 'build_canada'::character varying NOT NULL
);


--
-- Name: metrics_substack_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_substack_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_substack_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_substack_stats_id_seq OWNED BY public.metrics_substack_stats.id;


--
-- Name: metrics_twitter_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_twitter_stats (
    id bigint NOT NULL,
    account character varying NOT NULL,
    date date NOT NULL,
    impressions integer DEFAULT 0 NOT NULL,
    likes integer DEFAULT 0 NOT NULL,
    engagements integer DEFAULT 0 NOT NULL,
    bookmarks integer DEFAULT 0 NOT NULL,
    shares integer DEFAULT 0 NOT NULL,
    new_follows integer DEFAULT 0 NOT NULL,
    unfollows integer DEFAULT 0 NOT NULL,
    replies integer DEFAULT 0 NOT NULL,
    reposts integer DEFAULT 0 NOT NULL,
    profile_visits integer DEFAULT 0 NOT NULL,
    create_post integer DEFAULT 0 NOT NULL,
    video_views integer DEFAULT 0 NOT NULL,
    media_views integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_twitter_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_twitter_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_twitter_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_twitter_stats_id_seq OWNED BY public.metrics_twitter_stats.id;


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    hidden boolean DEFAULT false,
    published_at timestamp(6) without time zone,
    slug character varying NOT NULL,
    summary_en text,
    summary_fr text,
    title_en character varying,
    title_fr character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    body_md_en text,
    body_md_fr text
);


--
-- Name: posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.posts_id_seq OWNED BY public.posts.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: social_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.social_posts (
    id bigint NOT NULL,
    type character varying NOT NULL,
    account_handle character varying NOT NULL,
    external_id character varying NOT NULL,
    title character varying,
    body text,
    url character varying NOT NULL,
    image_url character varying,
    author_name character varying,
    author_avatar_url character varying,
    embed_code text,
    metadata jsonb DEFAULT '{}'::jsonb,
    posted_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: social_posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.social_posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: social_posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.social_posts_id_seq OWNED BY public.social_posts.id;


--
-- Name: subscribers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscribers (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    email character varying NOT NULL,
    first_name character varying,
    last_name character varying,
    postal_code character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: subscribers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscribers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscribers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscribers_id_seq OWNED BY public.subscribers.id;


--
-- Name: substack_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.substack_posts (
    id bigint NOT NULL,
    external_url character varying NOT NULL,
    title character varying NOT NULL,
    subtitle character varying,
    body text,
    author_name character varying,
    image_url character varying,
    posted_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: substack_posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.substack_posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: substack_posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.substack_posts_id_seq OWNED BY public.substack_posts.id;


--
-- Name: team_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_members (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    linkedin_url character varying,
    name character varying NOT NULL,
    "position" integer DEFAULT 0,
    published_at timestamp(6) without time zone,
    role character varying,
    slug character varying,
    title_en character varying,
    title_fr character varying,
    twitter_url character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: team_members_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_members_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_members_id_seq OWNED BY public.team_members.id;


--
-- Name: testimonials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.testimonials (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    "position" integer DEFAULT 0,
    published_at timestamp(6) without time zone,
    quote_en text,
    quote_fr text,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: testimonials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.testimonials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: testimonials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.testimonials_id_seq OWNED BY public.testimonials.id;


--
-- Name: tools; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tools (
    id bigint NOT NULL,
    accent_color character varying,
    created_at timestamp(6) without time zone NOT NULL,
    featured boolean DEFAULT false,
    "position" integer DEFAULT 0,
    published_at timestamp(6) without time zone,
    size character varying DEFAULT 'small'::character varying,
    slug character varying NOT NULL,
    title_en character varying,
    title_fr character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    url character varying,
    description_md_en text,
    description_md_fr text
);


--
-- Name: tools_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tools_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tools_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tools_id_seq OWNED BY public.tools.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    avatar_url character varying,
    created_at timestamp(6) without time zone NOT NULL,
    current_sign_in_at timestamp(6) without time zone,
    current_sign_in_ip character varying,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    last_sign_in_at timestamp(6) without time zone,
    last_sign_in_ip character varying,
    name character varying,
    provider character varying,
    remember_created_at timestamp(6) without time zone,
    reset_password_sent_at timestamp(6) without time zone,
    reset_password_token character varying,
    sign_in_count integer DEFAULT 0 NOT NULL,
    uid character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    role character varying DEFAULT 'member'::character varying NOT NULL,
    postal_code character varying,
    address_line1 character varying,
    address_line2 character varying,
    city character varying,
    province character varying
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: addresses; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.addresses (
    id bigint NOT NULL,
    oda_uid character varying NOT NULL,
    street_number character varying,
    street_name character varying,
    street_type character varying,
    street_direction character varying,
    unit character varying,
    city character varying,
    province_code character varying(2),
    postal_code character varying(7),
    full_address character varying,
    csd_uid character varying,
    csd_name character varying,
    latitude numeric(10,7),
    longitude numeric(11,7),
    provider character varying,
    raw_ingestion_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: addresses_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.addresses_id_seq OWNED BY warehouse.addresses.id;


--
-- Name: fiscal_authorities; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.fiscal_authorities (
    id bigint NOT NULL,
    amount numeric(15,2),
    created_at timestamp(6) without time zone NOT NULL,
    description text,
    document_type character varying NOT NULL,
    fiscal_year character varying NOT NULL,
    lineage_entry_id bigint,
    organization_id bigint NOT NULL,
    raw_ingestion_id bigint,
    updated_at timestamp(6) without time zone NOT NULL,
    vote_number character varying,
    vote_type character varying NOT NULL
);


--
-- Name: fiscal_authorities_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.fiscal_authorities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fiscal_authorities_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.fiscal_authorities_id_seq OWNED BY warehouse.fiscal_authorities.id;


--
-- Name: fiscal_expenditures; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.fiscal_expenditures (
    id bigint NOT NULL,
    actual_expenditure numeric(15,2),
    created_at timestamp(6) without time zone NOT NULL,
    description text,
    fiscal_year character varying NOT NULL,
    lineage_entry_id bigint,
    organization_id bigint NOT NULL,
    pa_voted_ceiling numeric(15,2),
    raw_ingestion_id bigint,
    updated_at timestamp(6) without time zone NOT NULL,
    vote_number character varying,
    vote_type character varying NOT NULL
);


--
-- Name: fiscal_expenditures_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.fiscal_expenditures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fiscal_expenditures_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.fiscal_expenditures_id_seq OWNED BY warehouse.fiscal_expenditures.id;


--
-- Name: geo_boundaries; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.geo_boundaries (
    id bigint NOT NULL,
    boundary_type character varying NOT NULL,
    geo_uid character varying NOT NULL,
    name_en character varying,
    name_fr character varying,
    province_code character varying(2),
    geometry public.geography(MultiPolygon,4326),
    population integer,
    area_sq_km numeric,
    census_year integer DEFAULT 2021,
    raw_ingestion_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: geo_boundaries_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.geo_boundaries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: geo_boundaries_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.geo_boundaries_id_seq OWNED BY warehouse.geo_boundaries.id;


--
-- Name: geo_crosswalks; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.geo_crosswalks (
    id bigint NOT NULL,
    source_id bigint NOT NULL,
    target_id bigint NOT NULL,
    source_type character varying NOT NULL,
    target_type character varying NOT NULL,
    overlap_population integer,
    weight_source_to_target numeric(10,8),
    weight_target_to_source numeric(10,8),
    da_count integer,
    census_year integer DEFAULT 2021,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: geo_crosswalks_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.geo_crosswalks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: geo_crosswalks_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.geo_crosswalks_id_seq OWNED BY warehouse.geo_crosswalks.id;


--
-- Name: geo_relationships; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.geo_relationships (
    id bigint NOT NULL,
    da_id bigint NOT NULL,
    parent_id bigint NOT NULL,
    relationship_type character varying NOT NULL,
    raw_ingestion_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: geo_relationships_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.geo_relationships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: geo_relationships_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.geo_relationships_id_seq OWNED BY warehouse.geo_relationships.id;


--
-- Name: lineage_entries; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.lineage_entries (
    id bigint NOT NULL,
    confidence numeric(5,4),
    created_at timestamp(6) without time zone NOT NULL,
    human_override boolean DEFAULT false,
    llm_model character varying,
    llm_prompt_snapshot jsonb,
    llm_response_snapshot jsonb,
    override_at timestamp(6) without time zone,
    override_by character varying,
    raw_ingestion_id bigint,
    source_field character varying,
    source_value character varying,
    target_field character varying,
    target_value character varying,
    transformation_type character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: lineage_entries_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.lineage_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lineage_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.lineage_entries_id_seq OWNED BY warehouse.lineage_entries.id;


--
-- Name: lobbying_activities; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.lobbying_activities (
    id bigint NOT NULL,
    client_name character varying,
    created_at timestamp(6) without time zone NOT NULL,
    end_date date,
    lineage_entry_id bigint,
    lobbyist_id bigint NOT NULL,
    organization_id bigint,
    raw_ingestion_id bigint,
    start_date date,
    status character varying,
    subject_matter character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: lobbying_activities_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.lobbying_activities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lobbying_activities_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.lobbying_activities_id_seq OWNED BY warehouse.lobbying_activities.id;


--
-- Name: lobbyists; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.lobbyists (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    lobbyist_type character varying,
    name character varying NOT NULL,
    registration_number character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: lobbyists_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.lobbyists_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lobbyists_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.lobbyists_id_seq OWNED BY warehouse.lobbyists.id;


--
-- Name: organization_aliases; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.organization_aliases (
    id bigint NOT NULL,
    alias_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    organization_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    valid_from date,
    valid_to date
);


--
-- Name: organization_aliases_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.organization_aliases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organization_aliases_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.organization_aliases_id_seq OWNED BY warehouse.organization_aliases.id;


--
-- Name: organizations; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.organizations (
    id bigint NOT NULL,
    canonical_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    needs_review boolean DEFAULT false NOT NULL,
    org_id_infobase integer,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: organizations_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organizations_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.organizations_id_seq OWNED BY warehouse.organizations.id;


--
-- Name: raw_ingestions; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.raw_ingestions (
    id bigint NOT NULL,
    checksum character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    error_message text,
    fetched_at timestamp(6) without time zone NOT NULL,
    raw_file_path character varying NOT NULL,
    source_id bigint NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: raw_ingestions_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.raw_ingestions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: raw_ingestions_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.raw_ingestions_id_seq OWNED BY warehouse.raw_ingestions.id;


--
-- Name: sources; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.sources (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    fetch_frequency character varying,
    format character varying NOT NULL,
    last_fetched_at timestamp(6) without time zone,
    name character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    url character varying NOT NULL
);


--
-- Name: sources_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sources_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.sources_id_seq OWNED BY warehouse.sources.id;


--
-- Name: spending_deviations; Type: VIEW; Schema: warehouse; Owner: -
--

CREATE VIEW warehouse.spending_deviations AS
 SELECT fa.organization_id,
    fa.fiscal_year,
    fa.vote_number,
    fa.vote_type,
    sum(fa.amount) AS consolidated_estimate,
    fe.actual_expenditure,
    (fe.actual_expenditure - sum(fa.amount)) AS variance_amount,
        CASE
            WHEN (sum(fa.amount) = (0)::numeric) THEN NULL::numeric
            ELSE round((((fe.actual_expenditure - sum(fa.amount)) / abs(sum(fa.amount))) * (100)::numeric), 2)
        END AS variance_pct
   FROM (warehouse.fiscal_authorities fa
     LEFT JOIN warehouse.fiscal_expenditures fe ON (((fa.organization_id = fe.organization_id) AND ((fa.fiscal_year)::text = (fe.fiscal_year)::text) AND ((fa.vote_number)::text = (fe.vote_number)::text))))
  GROUP BY fa.organization_id, fa.fiscal_year, fa.vote_number, fa.vote_type, fe.actual_expenditure;


--
-- Name: standard_object_expenditures; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.standard_object_expenditures (
    id bigint NOT NULL,
    amount numeric(15,2),
    created_at timestamp(6) without time zone NOT NULL,
    fiscal_year character varying NOT NULL,
    organization_id bigint NOT NULL,
    raw_ingestion_id bigint,
    standard_object character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: standard_object_expenditures_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.standard_object_expenditures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: standard_object_expenditures_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.standard_object_expenditures_id_seq OWNED BY warehouse.standard_object_expenditures.id;


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: builders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.builders ALTER COLUMN id SET DEFAULT nextval('public.builders_id_seq'::regclass);


--
-- Name: faqs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faqs ALTER COLUMN id SET DEFAULT nextval('public.faqs_id_seq'::regclass);


--
-- Name: feed_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feed_entries ALTER COLUMN id SET DEFAULT nextval('public.feed_entries_id_seq'::regclass);


--
-- Name: friendly_id_slugs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendly_id_slugs ALTER COLUMN id SET DEFAULT nextval('public.friendly_id_slugs_id_seq'::regclass);


--
-- Name: jwt_denylists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jwt_denylists ALTER COLUMN id SET DEFAULT nextval('public.jwt_denylists_id_seq'::regclass);


--
-- Name: memos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memos ALTER COLUMN id SET DEFAULT nextval('public.memos_id_seq'::regclass);


--
-- Name: metrics_linkedin_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_linkedin_stats ALTER COLUMN id SET DEFAULT nextval('public.metrics_linkedin_stats_id_seq'::regclass);


--
-- Name: metrics_substack_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_substack_stats ALTER COLUMN id SET DEFAULT nextval('public.metrics_substack_stats_id_seq'::regclass);


--
-- Name: metrics_twitter_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_twitter_stats ALTER COLUMN id SET DEFAULT nextval('public.metrics_twitter_stats_id_seq'::regclass);


--
-- Name: posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts ALTER COLUMN id SET DEFAULT nextval('public.posts_id_seq'::regclass);


--
-- Name: social_posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_posts ALTER COLUMN id SET DEFAULT nextval('public.social_posts_id_seq'::regclass);


--
-- Name: subscribers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscribers ALTER COLUMN id SET DEFAULT nextval('public.subscribers_id_seq'::regclass);


--
-- Name: substack_posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substack_posts ALTER COLUMN id SET DEFAULT nextval('public.substack_posts_id_seq'::regclass);


--
-- Name: team_members id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members ALTER COLUMN id SET DEFAULT nextval('public.team_members_id_seq'::regclass);


--
-- Name: testimonials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.testimonials ALTER COLUMN id SET DEFAULT nextval('public.testimonials_id_seq'::regclass);


--
-- Name: tools id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tools ALTER COLUMN id SET DEFAULT nextval('public.tools_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: addresses id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.addresses ALTER COLUMN id SET DEFAULT nextval('warehouse.addresses_id_seq'::regclass);


--
-- Name: fiscal_authorities id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_authorities ALTER COLUMN id SET DEFAULT nextval('warehouse.fiscal_authorities_id_seq'::regclass);


--
-- Name: fiscal_expenditures id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_expenditures ALTER COLUMN id SET DEFAULT nextval('warehouse.fiscal_expenditures_id_seq'::regclass);


--
-- Name: geo_boundaries id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_boundaries ALTER COLUMN id SET DEFAULT nextval('warehouse.geo_boundaries_id_seq'::regclass);


--
-- Name: geo_crosswalks id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_crosswalks ALTER COLUMN id SET DEFAULT nextval('warehouse.geo_crosswalks_id_seq'::regclass);


--
-- Name: geo_relationships id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_relationships ALTER COLUMN id SET DEFAULT nextval('warehouse.geo_relationships_id_seq'::regclass);


--
-- Name: lineage_entries id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lineage_entries ALTER COLUMN id SET DEFAULT nextval('warehouse.lineage_entries_id_seq'::regclass);


--
-- Name: lobbying_activities id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lobbying_activities ALTER COLUMN id SET DEFAULT nextval('warehouse.lobbying_activities_id_seq'::regclass);


--
-- Name: lobbyists id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lobbyists ALTER COLUMN id SET DEFAULT nextval('warehouse.lobbyists_id_seq'::regclass);


--
-- Name: organization_aliases id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_aliases ALTER COLUMN id SET DEFAULT nextval('warehouse.organization_aliases_id_seq'::regclass);


--
-- Name: organizations id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organizations ALTER COLUMN id SET DEFAULT nextval('warehouse.organizations_id_seq'::regclass);


--
-- Name: raw_ingestions id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.raw_ingestions ALTER COLUMN id SET DEFAULT nextval('warehouse.raw_ingestions_id_seq'::regclass);


--
-- Name: sources id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.sources ALTER COLUMN id SET DEFAULT nextval('warehouse.sources_id_seq'::regclass);


--
-- Name: standard_object_expenditures id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.standard_object_expenditures ALTER COLUMN id SET DEFAULT nextval('warehouse.standard_object_expenditures_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: builders builders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.builders
    ADD CONSTRAINT builders_pkey PRIMARY KEY (id);


--
-- Name: faqs faqs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faqs
    ADD CONSTRAINT faqs_pkey PRIMARY KEY (id);


--
-- Name: feed_entries feed_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feed_entries
    ADD CONSTRAINT feed_entries_pkey PRIMARY KEY (id);


--
-- Name: friendly_id_slugs friendly_id_slugs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendly_id_slugs
    ADD CONSTRAINT friendly_id_slugs_pkey PRIMARY KEY (id);


--
-- Name: jwt_denylists jwt_denylists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jwt_denylists
    ADD CONSTRAINT jwt_denylists_pkey PRIMARY KEY (id);


--
-- Name: memos memos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memos
    ADD CONSTRAINT memos_pkey PRIMARY KEY (id);


--
-- Name: metrics_linkedin_stats metrics_linkedin_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_linkedin_stats
    ADD CONSTRAINT metrics_linkedin_stats_pkey PRIMARY KEY (id);


--
-- Name: metrics_substack_stats metrics_substack_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_substack_stats
    ADD CONSTRAINT metrics_substack_stats_pkey PRIMARY KEY (id);


--
-- Name: metrics_twitter_stats metrics_twitter_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_twitter_stats
    ADD CONSTRAINT metrics_twitter_stats_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: social_posts social_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_posts
    ADD CONSTRAINT social_posts_pkey PRIMARY KEY (id);


--
-- Name: subscribers subscribers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscribers
    ADD CONSTRAINT subscribers_pkey PRIMARY KEY (id);


--
-- Name: substack_posts substack_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.substack_posts
    ADD CONSTRAINT substack_posts_pkey PRIMARY KEY (id);


--
-- Name: team_members team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (id);


--
-- Name: testimonials testimonials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.testimonials
    ADD CONSTRAINT testimonials_pkey PRIMARY KEY (id);


--
-- Name: tools tools_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tools
    ADD CONSTRAINT tools_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: addresses addresses_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.addresses
    ADD CONSTRAINT addresses_pkey PRIMARY KEY (id);


--
-- Name: fiscal_authorities fiscal_authorities_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_authorities
    ADD CONSTRAINT fiscal_authorities_pkey PRIMARY KEY (id);


--
-- Name: fiscal_expenditures fiscal_expenditures_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_expenditures
    ADD CONSTRAINT fiscal_expenditures_pkey PRIMARY KEY (id);


--
-- Name: geo_boundaries geo_boundaries_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_boundaries
    ADD CONSTRAINT geo_boundaries_pkey PRIMARY KEY (id);


--
-- Name: geo_crosswalks geo_crosswalks_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_crosswalks
    ADD CONSTRAINT geo_crosswalks_pkey PRIMARY KEY (id);


--
-- Name: geo_relationships geo_relationships_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_relationships
    ADD CONSTRAINT geo_relationships_pkey PRIMARY KEY (id);


--
-- Name: lineage_entries lineage_entries_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lineage_entries
    ADD CONSTRAINT lineage_entries_pkey PRIMARY KEY (id);


--
-- Name: lobbying_activities lobbying_activities_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lobbying_activities
    ADD CONSTRAINT lobbying_activities_pkey PRIMARY KEY (id);


--
-- Name: lobbyists lobbyists_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lobbyists
    ADD CONSTRAINT lobbyists_pkey PRIMARY KEY (id);


--
-- Name: organization_aliases organization_aliases_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_aliases
    ADD CONSTRAINT organization_aliases_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: raw_ingestions raw_ingestions_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.raw_ingestions
    ADD CONSTRAINT raw_ingestions_pkey PRIMARY KEY (id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);


--
-- Name: standard_object_expenditures standard_object_expenditures_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.standard_object_expenditures
    ADD CONSTRAINT standard_object_expenditures_pkey PRIMARY KEY (id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_builders_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_builders_on_slug ON public.builders USING btree (slug);


--
-- Name: index_faqs_on_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_faqs_on_position ON public.faqs USING btree ("position");


--
-- Name: index_feed_entries_on_featured; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feed_entries_on_featured ON public.feed_entries USING btree (featured);


--
-- Name: index_feed_entries_on_feedable_type_and_feedable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_feed_entries_on_feedable_type_and_feedable_id ON public.feed_entries USING btree (feedable_type, feedable_id);


--
-- Name: index_feed_entries_on_published_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feed_entries_on_published_at ON public.feed_entries USING btree (published_at DESC);


--
-- Name: index_feed_entries_on_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feed_entries_on_tags ON public.feed_entries USING gin (tags);


--
-- Name: index_friendly_id_slugs_on_slug_and_sluggable_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_friendly_id_slugs_on_slug_and_sluggable_type ON public.friendly_id_slugs USING btree (slug, sluggable_type);


--
-- Name: index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope ON public.friendly_id_slugs USING btree (slug, sluggable_type, scope);


--
-- Name: index_friendly_id_slugs_on_sluggable_type_and_sluggable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_friendly_id_slugs_on_sluggable_type_and_sluggable_id ON public.friendly_id_slugs USING btree (sluggable_type, sluggable_id);


--
-- Name: index_jwt_denylists_on_jti; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jwt_denylists_on_jti ON public.jwt_denylists USING btree (jti);


--
-- Name: index_memos_on_author_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memos_on_author_id ON public.memos USING btree (author_id);


--
-- Name: index_memos_on_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memos_on_category ON public.memos USING btree (category);


--
-- Name: index_memos_on_co_author_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memos_on_co_author_id ON public.memos USING btree (co_author_id);


--
-- Name: index_memos_on_featured; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memos_on_featured ON public.memos USING btree (featured);


--
-- Name: index_memos_on_publication; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memos_on_publication ON public.memos USING btree (publication);


--
-- Name: index_memos_on_published_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memos_on_published_at ON public.memos USING btree (published_at);


--
-- Name: index_memos_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memos_on_slug ON public.memos USING btree (slug);


--
-- Name: index_metrics_linkedin_stats_on_account_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metrics_linkedin_stats_on_account_and_date ON public.metrics_linkedin_stats USING btree (account, date);


--
-- Name: index_metrics_substack_stats_on_account_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metrics_substack_stats_on_account_and_date ON public.metrics_substack_stats USING btree (account, date);


--
-- Name: index_metrics_twitter_stats_on_account_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metrics_twitter_stats_on_account_and_date ON public.metrics_twitter_stats USING btree (account, date);


--
-- Name: index_posts_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_posts_on_slug ON public.posts USING btree (slug);


--
-- Name: index_social_posts_on_posted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_social_posts_on_posted_at ON public.social_posts USING btree (posted_at DESC);


--
-- Name: index_social_posts_on_type_and_account_handle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_social_posts_on_type_and_account_handle ON public.social_posts USING btree (type, account_handle);


--
-- Name: index_social_posts_on_type_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_social_posts_on_type_and_external_id ON public.social_posts USING btree (type, external_id);


--
-- Name: index_subscribers_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_subscribers_on_email ON public.subscribers USING btree (email);


--
-- Name: index_substack_posts_on_external_url; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_substack_posts_on_external_url ON public.substack_posts USING btree (external_url);


--
-- Name: index_substack_posts_on_posted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_substack_posts_on_posted_at ON public.substack_posts USING btree (posted_at DESC);


--
-- Name: index_team_members_on_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_members_on_position ON public.team_members USING btree ("position");


--
-- Name: index_team_members_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_members_on_role ON public.team_members USING btree (role);


--
-- Name: index_team_members_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_members_on_slug ON public.team_members USING btree (slug);


--
-- Name: index_testimonials_on_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_testimonials_on_position ON public.testimonials USING btree ("position");


--
-- Name: index_tools_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tools_on_slug ON public.tools USING btree (slug);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_provider_and_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_provider_and_uid ON public.users USING btree (provider, uid);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: idx_addresses_city; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_addresses_city ON warehouse.addresses USING btree (lower((city)::text));


--
-- Name: idx_addresses_city_trgm; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_addresses_city_trgm ON warehouse.addresses USING gin (city public.gin_trgm_ops);


--
-- Name: idx_addresses_csd_uid; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_addresses_csd_uid ON warehouse.addresses USING btree (csd_uid);


--
-- Name: idx_addresses_lat_lng; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_addresses_lat_lng ON warehouse.addresses USING btree (latitude, longitude);


--
-- Name: idx_addresses_oda_uid; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_addresses_oda_uid ON warehouse.addresses USING btree (oda_uid);


--
-- Name: idx_addresses_postal_code; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_addresses_postal_code ON warehouse.addresses USING btree (postal_code);


--
-- Name: idx_addresses_province_code; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_addresses_province_code ON warehouse.addresses USING btree (province_code);


--
-- Name: idx_addresses_street; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_addresses_street ON warehouse.addresses USING btree (lower((street_name)::text));


--
-- Name: idx_addresses_street_name_trgm; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_addresses_street_name_trgm ON warehouse.addresses USING gin (street_name public.gin_trgm_ops);


--
-- Name: idx_fiscal_authorities_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_fiscal_authorities_unique ON warehouse.fiscal_authorities USING btree (organization_id, fiscal_year, document_type, vote_number);


--
-- Name: idx_fiscal_expenditures_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_fiscal_expenditures_unique ON warehouse.fiscal_expenditures USING btree (organization_id, fiscal_year, vote_number);


--
-- Name: idx_geo_boundaries_geometry; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_geo_boundaries_geometry ON warehouse.geo_boundaries USING gist (geometry);


--
-- Name: idx_geo_boundaries_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_geo_boundaries_unique ON warehouse.geo_boundaries USING btree (boundary_type, geo_uid, census_year);


--
-- Name: idx_geo_crosswalks_source; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_geo_crosswalks_source ON warehouse.geo_crosswalks USING btree (source_type, source_id);


--
-- Name: idx_geo_crosswalks_target; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_geo_crosswalks_target ON warehouse.geo_crosswalks USING btree (target_type, target_id);


--
-- Name: idx_geo_crosswalks_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_geo_crosswalks_unique ON warehouse.geo_crosswalks USING btree (source_id, target_id, census_year);


--
-- Name: idx_geo_relationships_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_geo_relationships_unique ON warehouse.geo_relationships USING btree (da_id, parent_id, relationship_type);


--
-- Name: idx_std_obj_expenditures_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_std_obj_expenditures_unique ON warehouse.standard_object_expenditures USING btree (organization_id, fiscal_year, standard_object);


--
-- Name: index_fiscal_authorities_on_lineage_entry_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_fiscal_authorities_on_lineage_entry_id ON warehouse.fiscal_authorities USING btree (lineage_entry_id);


--
-- Name: index_fiscal_authorities_on_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_fiscal_authorities_on_organization_id ON warehouse.fiscal_authorities USING btree (organization_id);


--
-- Name: index_fiscal_authorities_on_raw_ingestion_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_fiscal_authorities_on_raw_ingestion_id ON warehouse.fiscal_authorities USING btree (raw_ingestion_id);


--
-- Name: index_fiscal_expenditures_on_lineage_entry_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_fiscal_expenditures_on_lineage_entry_id ON warehouse.fiscal_expenditures USING btree (lineage_entry_id);


--
-- Name: index_fiscal_expenditures_on_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_fiscal_expenditures_on_organization_id ON warehouse.fiscal_expenditures USING btree (organization_id);


--
-- Name: index_fiscal_expenditures_on_raw_ingestion_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_fiscal_expenditures_on_raw_ingestion_id ON warehouse.fiscal_expenditures USING btree (raw_ingestion_id);


--
-- Name: index_geo_boundaries_on_boundary_type; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_geo_boundaries_on_boundary_type ON warehouse.geo_boundaries USING btree (boundary_type);


--
-- Name: index_geo_boundaries_on_province_code; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_geo_boundaries_on_province_code ON warehouse.geo_boundaries USING btree (province_code);


--
-- Name: index_geo_relationships_on_da_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_geo_relationships_on_da_id ON warehouse.geo_relationships USING btree (da_id);


--
-- Name: index_geo_relationships_on_parent_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_geo_relationships_on_parent_id ON warehouse.geo_relationships USING btree (parent_id);


--
-- Name: index_geo_relationships_on_raw_ingestion_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_geo_relationships_on_raw_ingestion_id ON warehouse.geo_relationships USING btree (raw_ingestion_id);


--
-- Name: index_lineage_entries_on_raw_ingestion_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_lineage_entries_on_raw_ingestion_id ON warehouse.lineage_entries USING btree (raw_ingestion_id);


--
-- Name: index_lobbying_activities_on_lineage_entry_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_lobbying_activities_on_lineage_entry_id ON warehouse.lobbying_activities USING btree (lineage_entry_id);


--
-- Name: index_lobbying_activities_on_lobbyist_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_lobbying_activities_on_lobbyist_id ON warehouse.lobbying_activities USING btree (lobbyist_id);


--
-- Name: index_lobbying_activities_on_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_lobbying_activities_on_organization_id ON warehouse.lobbying_activities USING btree (organization_id);


--
-- Name: index_lobbying_activities_on_raw_ingestion_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_lobbying_activities_on_raw_ingestion_id ON warehouse.lobbying_activities USING btree (raw_ingestion_id);


--
-- Name: index_lobbyists_on_registration_number; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_lobbyists_on_registration_number ON warehouse.lobbyists USING btree (registration_number) WHERE (registration_number IS NOT NULL);


--
-- Name: index_organization_aliases_on_alias_name_and_valid_from; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_organization_aliases_on_alias_name_and_valid_from ON warehouse.organization_aliases USING btree (alias_name, valid_from);


--
-- Name: index_organization_aliases_on_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_organization_aliases_on_organization_id ON warehouse.organization_aliases USING btree (organization_id);


--
-- Name: index_organizations_on_canonical_name; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_canonical_name ON warehouse.organizations USING btree (canonical_name);


--
-- Name: index_organizations_on_org_id_infobase; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_org_id_infobase ON warehouse.organizations USING btree (org_id_infobase) WHERE (org_id_infobase IS NOT NULL);


--
-- Name: index_raw_ingestions_on_source_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_raw_ingestions_on_source_id ON warehouse.raw_ingestions USING btree (source_id);


--
-- Name: index_raw_ingestions_on_source_id_and_checksum; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_raw_ingestions_on_source_id_and_checksum ON warehouse.raw_ingestions USING btree (source_id, checksum);


--
-- Name: index_sources_on_name; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_sources_on_name ON warehouse.sources USING btree (name);


--
-- Name: index_standard_object_expenditures_on_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_standard_object_expenditures_on_organization_id ON warehouse.standard_object_expenditures USING btree (organization_id);


--
-- Name: index_standard_object_expenditures_on_raw_ingestion_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_standard_object_expenditures_on_raw_ingestion_id ON warehouse.standard_object_expenditures USING btree (raw_ingestion_id);


--
-- Name: memos fk_rails_03b1037082; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memos
    ADD CONSTRAINT fk_rails_03b1037082 FOREIGN KEY (author_id) REFERENCES public.team_members(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: memos fk_rails_a7adfa8924; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memos
    ADD CONSTRAINT fk_rails_a7adfa8924 FOREIGN KEY (co_author_id) REFERENCES public.team_members(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: addresses addresses_raw_ingestion_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.addresses
    ADD CONSTRAINT addresses_raw_ingestion_id_fkey FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: lobbying_activities fk_rails_0229443ca4; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lobbying_activities
    ADD CONSTRAINT fk_rails_0229443ca4 FOREIGN KEY (organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: fiscal_authorities fk_rails_0cfba20653; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_authorities
    ADD CONSTRAINT fk_rails_0cfba20653 FOREIGN KEY (lineage_entry_id) REFERENCES warehouse.lineage_entries(id);


--
-- Name: lobbying_activities fk_rails_1e146f8e23; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lobbying_activities
    ADD CONSTRAINT fk_rails_1e146f8e23 FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: fiscal_expenditures fk_rails_1f60531add; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_expenditures
    ADD CONSTRAINT fk_rails_1f60531add FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: fiscal_expenditures fk_rails_34d506f249; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_expenditures
    ADD CONSTRAINT fk_rails_34d506f249 FOREIGN KEY (organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: fiscal_expenditures fk_rails_3a07710e6e; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_expenditures
    ADD CONSTRAINT fk_rails_3a07710e6e FOREIGN KEY (lineage_entry_id) REFERENCES warehouse.lineage_entries(id);


--
-- Name: lineage_entries fk_rails_508c5de983; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lineage_entries
    ADD CONSTRAINT fk_rails_508c5de983 FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: fiscal_authorities fk_rails_847d2d9f3d; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_authorities
    ADD CONSTRAINT fk_rails_847d2d9f3d FOREIGN KEY (organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: lobbying_activities fk_rails_8ce58f15fd; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lobbying_activities
    ADD CONSTRAINT fk_rails_8ce58f15fd FOREIGN KEY (lineage_entry_id) REFERENCES warehouse.lineage_entries(id);


--
-- Name: fiscal_authorities fk_rails_9d49a9edcc; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.fiscal_authorities
    ADD CONSTRAINT fk_rails_9d49a9edcc FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: raw_ingestions fk_rails_a9396928a6; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.raw_ingestions
    ADD CONSTRAINT fk_rails_a9396928a6 FOREIGN KEY (source_id) REFERENCES warehouse.sources(id);


--
-- Name: organization_aliases fk_rails_b725450d43; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_aliases
    ADD CONSTRAINT fk_rails_b725450d43 FOREIGN KEY (organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: standard_object_expenditures fk_rails_c3f430a0df; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.standard_object_expenditures
    ADD CONSTRAINT fk_rails_c3f430a0df FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: standard_object_expenditures fk_rails_e3fb24df7c; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.standard_object_expenditures
    ADD CONSTRAINT fk_rails_e3fb24df7c FOREIGN KEY (organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: lobbying_activities fk_rails_f90a35864a; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lobbying_activities
    ADD CONSTRAINT fk_rails_f90a35864a FOREIGN KEY (lobbyist_id) REFERENCES warehouse.lobbyists(id);


--
-- Name: geo_boundaries geo_boundaries_raw_ingestion_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_boundaries
    ADD CONSTRAINT geo_boundaries_raw_ingestion_id_fkey FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: geo_crosswalks geo_crosswalks_source_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_crosswalks
    ADD CONSTRAINT geo_crosswalks_source_id_fkey FOREIGN KEY (source_id) REFERENCES warehouse.geo_boundaries(id);


--
-- Name: geo_crosswalks geo_crosswalks_target_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_crosswalks
    ADD CONSTRAINT geo_crosswalks_target_id_fkey FOREIGN KEY (target_id) REFERENCES warehouse.geo_boundaries(id);


--
-- Name: geo_relationships geo_relationships_da_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_relationships
    ADD CONSTRAINT geo_relationships_da_id_fkey FOREIGN KEY (da_id) REFERENCES warehouse.geo_boundaries(id);


--
-- Name: geo_relationships geo_relationships_parent_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_relationships
    ADD CONSTRAINT geo_relationships_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES warehouse.geo_boundaries(id);


--
-- Name: geo_relationships geo_relationships_raw_ingestion_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geo_relationships
    ADD CONSTRAINT geo_relationships_raw_ingestion_id_fkey FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO public,warehouse;

INSERT INTO "schema_migrations" (version) VALUES
('20260423202720'),
('20260422000003'),
('20260422000002'),
('20260422000001'),
('20260421224245'),
('20260420195921'),
('20260413000000'),
('20260412050000'),
('20260412045451'),
('20260412035425'),
('20260412035424'),
('20260412035423'),
('20260412035422'),
('20260412035421'),
('20260409200003'),
('20260409200002'),
('20260409200001'),
('20260409200000'),
('20260406043854'),
('20260403210357'),
('20260326200001'),
('20260326184648'),
('20260326184647'),
('20260324230847'),
('20260324230846'),
('20260324230735'),
('20260324010009'),
('20260324010008'),
('20260324010007'),
('20260324010006'),
('20260324010005'),
('20260324010004'),
('20260324010003'),
('20260324010002'),
('20260324010001'),
('20260323081911'),
('20260323010610'),
('20260323010606'),
('20260323010605'),
('20260323010601'),
('20260323010600'),
('20260323010559'),
('20260323010554'),
('20260323010553'),
('20260323010552'),
('20260323010551'),
('20260323010543');

