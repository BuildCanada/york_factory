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


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


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
-- Name: api_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_keys (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    name character varying NOT NULL,
    token_digest character varying NOT NULL,
    token_prefix character varying NOT NULL,
    last_used_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: api_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_keys_id_seq OWNED BY public.api_keys.id;


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
-- Name: engagements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.engagements (
    id bigint NOT NULL,
    type character varying NOT NULL,
    memo_id bigint NOT NULL,
    user_id bigint NOT NULL,
    body text,
    status integer DEFAULT 0 NOT NULL,
    published_at timestamp(6) without time zone,
    moderated_by_id bigint,
    moderated_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: engagements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.engagements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: engagements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.engagements_id_seq OWNED BY public.engagements.id;


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
-- Name: hubspot_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hubspot_contacts (
    id bigint NOT NULL,
    hubspot_contact_id character varying,
    email character varying,
    firstname character varying,
    lastname character varying,
    phone character varying,
    company character varying,
    city character varying,
    country character varying,
    website character varying,
    background text,
    linkedin_url character varying,
    bluesky_handle character varying,
    twitter_handle character varying,
    create_date timestamp(6) without time zone,
    last_activity_date timestamp(6) without time zone,
    email_confirmed boolean,
    raw_properties jsonb,
    synced_at timestamp(6) without time zone,
    member_source character varying,
    joined_at timestamp(6) without time zone,
    provincial_constituency character varying,
    federal_constituency character varying,
    zip character varying,
    hs_state_code character varying,
    state character varying,
    hs_marketable_status character varying,
    discord_join_date timestamp(6) without time zone,
    is_member boolean,
    discord_username character varying,
    whatsapp_groups text,
    twitter_subscriptions text,
    substack_subscriptions text,
    num_unique_conversion_events integer,
    first_conversion_event_name character varying,
    role boolean,
    message character varying,
    industry character varying,
    jobtitle character varying,
    house_rules boolean,
    full_name character varying,
    interests character varying,
    skillsets character varying,
    ip_country character varying,
    ip_city character varying,
    ip_state character varying,
    the_basics character varying,
    hs_timezone character varying,
    time_commitment character varying,
    substack_handle character varying,
    hs_latest_source character varying,
    associatedcompanyid character varying,
    profession character varying,
    skills text,
    work_interest text,
    about_accomplishments text,
    non_partisan_agreement boolean,
    postal_code character varying,
    province character varying,
    country_code character varying,
    latitude numeric(10,7),
    longitude numeric(10,7),
    timezone character varying,
    raw_constituencies jsonb,
    newsletter_subscription boolean DEFAULT true,
    hs_createdate timestamp(6) without time zone,
    hs_object_source_label character varying,
    hs_object_source_detail_1 character varying,
    member_join_date timestamp(6) without time zone,
    discord_display_name text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    pledged_to_vote_at timestamp(6) without time zone
);


--
-- Name: hubspot_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hubspot_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hubspot_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hubspot_contacts_id_seq OWNED BY public.hubspot_contacts.id;


--
-- Name: identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identities (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    provider character varying NOT NULL,
    uid character varying NOT NULL,
    email character varying,
    avatar_url character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    raw jsonb,
    access_token text,
    refresh_token text,
    token_expires_at timestamp(6) without time zone,
    token_scope character varying
);


--
-- Name: identities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identities_id_seq OWNED BY public.identities.id;


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
-- Name: luma_event_guests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.luma_event_guests (
    id bigint NOT NULL,
    luma_event_id bigint NOT NULL,
    luma_user_id character varying NOT NULL,
    name character varying,
    email character varying,
    approval_status character varying,
    checked_in boolean DEFAULT false,
    checked_in_at timestamp(6) without time zone,
    registered_at timestamp(6) without time zone,
    guest_data jsonb DEFAULT '{}'::jsonb,
    last_synced_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: luma_event_guests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.luma_event_guests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: luma_event_guests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.luma_event_guests_id_seq OWNED BY public.luma_event_guests.id;


--
-- Name: luma_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.luma_events (
    id bigint NOT NULL,
    luma_event_id character varying NOT NULL,
    name text,
    description text,
    start_at timestamp(6) without time zone,
    end_at timestamp(6) without time zone,
    timezone character varying,
    visibility character varying,
    url character varying,
    location_name character varying,
    location_address text,
    created_at_luma timestamp(6) without time zone,
    updated_at_luma timestamp(6) without time zone,
    event_data jsonb DEFAULT '{}'::jsonb,
    last_synced_at timestamp(6) without time zone,
    hubspot_synced_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: luma_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.luma_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: luma_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.luma_events_id_seq OWNED BY public.luma_events.id;


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
    publication character varying DEFAULT 'build_canada'::character varying NOT NULL,
    endorsements_count integer DEFAULT 0 NOT NULL,
    approved_critiques_count integer DEFAULT 0 NOT NULL
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
-- Name: metrics_instagram_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_instagram_stats (
    id bigint NOT NULL,
    account character varying DEFAULT 'build_canada'::character varying NOT NULL,
    date date NOT NULL,
    views integer,
    interactions integer,
    new_followers integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    social_media_account_id bigint
);


--
-- Name: metrics_instagram_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_instagram_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_instagram_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_instagram_stats_id_seq OWNED BY public.metrics_instagram_stats.id;


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
    account character varying DEFAULT 'build_canada'::character varying NOT NULL,
    social_media_account_id bigint
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
-- Name: metrics_social_media_account_metric_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_account_metric_snapshots (
    id bigint NOT NULL,
    social_media_account_id bigint NOT NULL,
    observed_at timestamp(6) without time zone NOT NULL,
    scraped_at timestamp(6) without time zone NOT NULL,
    followers_count bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_social_media_account_metric_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_account_metric_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_account_metric_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_account_metric_snapshots_id_seq OWNED BY public.metrics_social_media_account_metric_snapshots.id;


--
-- Name: metrics_social_media_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_accounts (
    id bigint NOT NULL,
    zernio_account_id character varying NOT NULL,
    zernio_profile_id character varying NOT NULL,
    profile_name character varying NOT NULL,
    platform character varying NOT NULL,
    account_key character varying NOT NULL,
    username character varying NOT NULL,
    display_name character varying,
    profile_url character varying,
    enabled boolean DEFAULT true NOT NULL,
    source_updated_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    ads_status character varying
);


--
-- Name: metrics_social_media_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_accounts_id_seq OWNED BY public.metrics_social_media_accounts.id;


--
-- Name: metrics_social_media_ad_account_daily_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_ad_account_daily_metrics (
    id bigint NOT NULL,
    ad_account_id bigint NOT NULL,
    date date NOT NULL,
    spend numeric(18,6),
    impressions bigint,
    reach bigint,
    clicks bigint,
    engagements bigint,
    conversions numeric(18,6),
    conversion_value numeric(18,6),
    ctr numeric(18,8),
    cpc numeric(18,8),
    cpm numeric(18,8),
    cost_per_conversion numeric(18,8),
    roas numeric(18,8),
    source_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_social_media_ad_account_daily_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_ad_account_daily_metrics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_ad_account_daily_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_ad_account_daily_metrics_id_seq OWNED BY public.metrics_social_media_ad_account_daily_metrics.id;


--
-- Name: metrics_social_media_ad_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_ad_accounts (
    id bigint NOT NULL,
    social_media_account_id bigint NOT NULL,
    platform_ad_account_id character varying NOT NULL,
    platform character varying NOT NULL,
    name character varying,
    business_name character varying,
    status character varying,
    currency character varying,
    timezone_name character varying,
    timezone_offset_hours numeric(8,2),
    minimum_daily_budget numeric(18,6),
    selectable boolean,
    unusable_reason character varying,
    backfill_pending boolean DEFAULT false NOT NULL,
    source_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    analytics_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_social_media_ad_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_ad_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_ad_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_ad_accounts_id_seq OWNED BY public.metrics_social_media_ad_accounts.id;


--
-- Name: metrics_social_media_ad_campaign_daily_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_ad_campaign_daily_metrics (
    id bigint NOT NULL,
    campaign_id bigint NOT NULL,
    date date NOT NULL,
    spend numeric(18,6),
    impressions bigint,
    reach bigint,
    clicks bigint,
    engagements bigint,
    conversions numeric(18,6),
    conversion_value numeric(18,6),
    ctr numeric(18,8),
    cpc numeric(18,8),
    cpm numeric(18,8),
    cost_per_conversion numeric(18,8),
    roas numeric(18,8),
    source_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_social_media_ad_campaign_daily_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_ad_campaign_daily_metrics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_ad_campaign_daily_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_ad_campaign_daily_metrics_id_seq OWNED BY public.metrics_social_media_ad_campaign_daily_metrics.id;


--
-- Name: metrics_social_media_ad_campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_ad_campaigns (
    id bigint NOT NULL,
    social_media_account_id bigint NOT NULL,
    ad_account_id bigint,
    platform_campaign_id character varying NOT NULL,
    platform_ad_account_id character varying,
    platform character varying NOT NULL,
    name character varying,
    status character varying,
    currency character varying,
    channel_type character varying,
    ad_count integer,
    external boolean DEFAULT false NOT NULL,
    platform_created_at timestamp(6) without time zone,
    earliest_ad_at timestamp(6) without time zone,
    latest_ad_at timestamp(6) without time zone,
    backfill_pending boolean DEFAULT false NOT NULL,
    budget_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    metrics_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_social_media_ad_campaigns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_ad_campaigns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_ad_campaigns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_ad_campaigns_id_seq OWNED BY public.metrics_social_media_ad_campaigns.id;


--
-- Name: metrics_social_media_ad_daily_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_ad_daily_metrics (
    id bigint NOT NULL,
    ad_id bigint NOT NULL,
    date date NOT NULL,
    spend numeric(18,6),
    impressions bigint,
    reach bigint,
    clicks bigint,
    engagements bigint,
    conversions numeric(18,6),
    conversion_value numeric(18,6),
    ctr numeric(18,8),
    cpc numeric(18,8),
    cpm numeric(18,8),
    cost_per_conversion numeric(18,8),
    roas numeric(18,8),
    source_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_social_media_ad_daily_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_ad_daily_metrics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_ad_daily_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_ad_daily_metrics_id_seq OWNED BY public.metrics_social_media_ad_daily_metrics.id;


--
-- Name: metrics_social_media_ads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_ads (
    id bigint NOT NULL,
    social_media_account_id bigint NOT NULL,
    ad_account_id bigint,
    campaign_id bigint,
    zernio_ad_id character varying NOT NULL,
    platform_ad_id character varying,
    platform_ad_account_id character varying,
    platform_campaign_id character varying,
    platform_ad_set_id character varying,
    platform character varying NOT NULL,
    name character varying,
    ad_set_name character varying,
    status character varying,
    goal character varying,
    ad_type character varying,
    currency character varying,
    external boolean DEFAULT false NOT NULL,
    platform_created_at timestamp(6) without time zone,
    source_updated_at timestamp(6) without time zone,
    last_synced_at timestamp(6) without time zone,
    backfill_pending boolean DEFAULT false NOT NULL,
    creative_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    metrics_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_social_media_ads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_ads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_ads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_ads_id_seq OWNED BY public.metrics_social_media_ads.id;


--
-- Name: metrics_social_media_post_metric_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_post_metric_snapshots (
    id bigint NOT NULL,
    social_media_post_id bigint NOT NULL,
    observed_at timestamp(6) without time zone NOT NULL,
    scraped_at timestamp(6) without time zone NOT NULL,
    impressions bigint DEFAULT 0 NOT NULL,
    reach bigint DEFAULT 0 NOT NULL,
    likes bigint DEFAULT 0 NOT NULL,
    comments bigint DEFAULT 0 NOT NULL,
    shares bigint DEFAULT 0 NOT NULL,
    saves bigint DEFAULT 0 NOT NULL,
    clicks bigint DEFAULT 0 NOT NULL,
    views bigint DEFAULT 0 NOT NULL,
    follows bigint DEFAULT 0 NOT NULL,
    reels_average_watch_time bigint DEFAULT 0 NOT NULL,
    reels_total_watch_time bigint DEFAULT 0 NOT NULL,
    video_duration_seconds numeric(12,3),
    engagement_rate numeric(12,6),
    source_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_social_media_post_metric_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_post_metric_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_post_metric_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_post_metric_snapshots_id_seq OWNED BY public.metrics_social_media_post_metric_snapshots.id;


--
-- Name: metrics_social_media_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_social_media_posts (
    id bigint NOT NULL,
    social_media_account_id bigint NOT NULL,
    social_post_id bigint,
    zernio_post_id character varying NOT NULL,
    late_post_id character varying,
    platform_post_id character varying,
    platform character varying NOT NULL,
    account_username character varying,
    status character varying NOT NULL,
    content text,
    platform_post_url character varying,
    thumbnail_url character varying,
    media_type character varying,
    published_at timestamp(6) without time zone,
    scheduled_for timestamp(6) without time zone,
    external boolean DEFAULT false NOT NULL,
    ad boolean DEFAULT false NOT NULL,
    source_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metrics_social_media_posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_social_media_posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_social_media_posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_social_media_posts_id_seq OWNED BY public.metrics_social_media_posts.id;


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
-- Name: metrics_tiktok_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics_tiktok_stats (
    id bigint NOT NULL,
    account character varying DEFAULT 'build_canada'::character varying NOT NULL,
    date date NOT NULL,
    video_views integer DEFAULT 0 NOT NULL,
    profile_views integer DEFAULT 0 NOT NULL,
    likes integer DEFAULT 0 NOT NULL,
    comments integer DEFAULT 0 NOT NULL,
    shares integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    social_media_account_id bigint
);


--
-- Name: metrics_tiktok_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_tiktok_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_tiktok_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_tiktok_stats_id_seq OWNED BY public.metrics_tiktok_stats.id;


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
    updated_at timestamp(6) without time zone NOT NULL,
    social_media_account_id bigint
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
-- Name: notification_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_batches (
    id bigint NOT NULL,
    saved_search_id bigint NOT NULL,
    mode character varying NOT NULL,
    state character varying DEFAULT 'open'::character varying NOT NULL,
    scheduled_for timestamp with time zone,
    closed_at timestamp with time zone,
    coalesced boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT notification_batches_mode CHECK (((mode)::text = ANY ((ARRAY['instant'::character varying, 'digest'::character varying])::text[]))),
    CONSTRAINT notification_batches_state CHECK (((state)::text = ANY ((ARRAY['open'::character varying, 'closed'::character varying, 'delivering'::character varying, 'delivered'::character varying, 'dead'::character varying])::text[])))
);


--
-- Name: notification_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_batches_id_seq OWNED BY public.notification_batches.id;


--
-- Name: notification_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_deliveries (
    id bigint NOT NULL,
    notification_batch_id bigint NOT NULL,
    channel character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    idempotency_key character varying NOT NULL,
    provider_response jsonb DEFAULT '{}'::jsonb NOT NULL,
    next_attempt_at timestamp with time zone,
    delivered_at timestamp with time zone,
    last_error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT notification_deliveries_channel CHECK (((channel)::text = 'email'::text)),
    CONSTRAINT notification_deliveries_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'delivering'::character varying, 'delivered'::character varying, 'failed'::character varying, 'dead'::character varying])::text[])))
);


--
-- Name: notification_deliveries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_deliveries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_deliveries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_deliveries_id_seq OWNED BY public.notification_deliveries.id;


--
-- Name: oauth_access_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_grants (
    id bigint NOT NULL,
    resource_owner_id bigint NOT NULL,
    application_id bigint NOT NULL,
    token character varying NOT NULL,
    expires_in integer NOT NULL,
    redirect_uri text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone
);


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_access_grants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_access_grants_id_seq OWNED BY public.oauth_access_grants.id;


--
-- Name: oauth_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_tokens (
    id bigint NOT NULL,
    resource_owner_id bigint,
    application_id bigint NOT NULL,
    token character varying NOT NULL,
    refresh_token character varying,
    expires_in integer,
    scopes character varying,
    created_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    previous_refresh_token character varying DEFAULT ''::character varying NOT NULL
);


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_access_tokens_id_seq OWNED BY public.oauth_access_tokens.id;


--
-- Name: oauth_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_applications (
    id bigint NOT NULL,
    name character varying NOT NULL,
    uid character varying NOT NULL,
    secret character varying NOT NULL,
    redirect_uri text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    confidential boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    trusted boolean DEFAULT false NOT NULL
);


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_applications_id_seq OWNED BY public.oauth_applications.id;


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
-- Name: saved_search_matches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_search_matches (
    id bigint NOT NULL,
    saved_search_id bigint NOT NULL,
    searchable_revision integer NOT NULL,
    searchable_content_hash character varying NOT NULL,
    match_key character varying NOT NULL,
    matched_at timestamp with time zone NOT NULL,
    matched_sequence bigint,
    match_evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    state character varying DEFAULT 'pending'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    searchable_type character varying NOT NULL,
    searchable_id character varying NOT NULL,
    notification_batch_id bigint,
    CONSTRAINT saved_search_matches_state CHECK (((state)::text = ANY ((ARRAY['pending'::character varying, 'buffered'::character varying, 'dispatching'::character varying, 'delivered'::character varying, 'dead'::character varying])::text[])))
);


--
-- Name: saved_search_matches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.saved_search_matches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saved_search_matches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.saved_search_matches_id_seq OWNED BY public.saved_search_matches.id;


--
-- Name: saved_search_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_search_runs (
    id bigint NOT NULL,
    saved_search_id bigint NOT NULL,
    scheduled_for timestamp with time zone NOT NULL,
    from_sequence bigint DEFAULT 0 NOT NULL,
    to_sequence bigint DEFAULT 0 NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    query_count integer DEFAULT 0 NOT NULL,
    matched_count integer DEFAULT 0 NOT NULL,
    duration_ms integer,
    billing jsonb DEFAULT '{}'::jsonb NOT NULL,
    performance jsonb DEFAULT '{}'::jsonb NOT NULL,
    error text,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT saved_search_runs_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying, 'succeeded'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: saved_search_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.saved_search_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saved_search_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.saved_search_runs_id_seq OWNED BY public.saved_search_runs.id;


--
-- Name: saved_searches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_searches (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    name character varying NOT NULL,
    realm character varying NOT NULL,
    definition jsonb DEFAULT '{}'::jsonb NOT NULL,
    definition_digest character varying NOT NULL,
    definition_version integer DEFAULT 1 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    poll_interval_seconds integer DEFAULT 60 NOT NULL,
    next_run_at timestamp with time zone,
    cursor_sequence bigint DEFAULT 0 NOT NULL,
    start_policy character varying DEFAULT 'future_only'::character varying NOT NULL,
    notify_on_update boolean DEFAULT false NOT NULL,
    delivery_mode character varying DEFAULT 'instant'::character varying NOT NULL,
    delivery_configuration jsonb DEFAULT '{"channels": ["email"]}'::jsonb NOT NULL,
    timezone character varying DEFAULT 'UTC'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT saved_searches_delivery_mode CHECK (((delivery_mode)::text = ANY ((ARRAY['instant'::character varying, 'digest'::character varying])::text[]))),
    CONSTRAINT saved_searches_poll_interval CHECK (((poll_interval_seconds >= 60) AND (poll_interval_seconds <= 86400))),
    CONSTRAINT saved_searches_start_policy CHECK (((start_policy)::text = ANY ((ARRAY['future_only'::character varying, 'backfill'::character varying])::text[])))
);


--
-- Name: saved_searches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.saved_searches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saved_searches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.saved_searches_id_seq OWNED BY public.saved_searches.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: search_index_sequence; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.search_index_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


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
    updated_at timestamp(6) without time zone NOT NULL,
    source character varying,
    placement character varying,
    page_uri character varying,
    page_name character varying,
    hubspot_utk character varying,
    ip_address character varying,
    pledged_to_vote_at timestamp(6) without time zone
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
-- Name: trade_barriers_agreement_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trade_barriers_agreement_histories (
    id bigint NOT NULL,
    agreement_id bigint NOT NULL,
    status character varying NOT NULL,
    date_entered date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: trade_barriers_agreement_histories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trade_barriers_agreement_histories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trade_barriers_agreement_histories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trade_barriers_agreement_histories_id_seq OWNED BY public.trade_barriers_agreement_histories.id;


--
-- Name: trade_barriers_agreement_jurisdictions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trade_barriers_agreement_jurisdictions (
    id bigint NOT NULL,
    agreement_id bigint NOT NULL,
    jurisdiction_id bigint NOT NULL,
    status character varying DEFAULT 'unknown'::character varying NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: trade_barriers_agreement_jurisdictions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trade_barriers_agreement_jurisdictions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trade_barriers_agreement_jurisdictions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trade_barriers_agreement_jurisdictions_id_seq OWNED BY public.trade_barriers_agreement_jurisdictions.id;


--
-- Name: trade_barriers_agreements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trade_barriers_agreements (
    id bigint NOT NULL,
    title character varying NOT NULL,
    slug character varying NOT NULL,
    summary text,
    description text,
    deadline date,
    launch_date date,
    source_url character varying,
    status character varying DEFAULT 'awaiting_sponsorship'::character varying NOT NULL,
    theme_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: trade_barriers_agreements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trade_barriers_agreements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trade_barriers_agreements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trade_barriers_agreements_id_seq OWNED BY public.trade_barriers_agreements.id;


--
-- Name: trade_barriers_jurisdiction_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trade_barriers_jurisdiction_histories (
    id bigint NOT NULL,
    agreement_jurisdiction_id bigint NOT NULL,
    status character varying NOT NULL,
    date_entered date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: trade_barriers_jurisdiction_histories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trade_barriers_jurisdiction_histories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trade_barriers_jurisdiction_histories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trade_barriers_jurisdiction_histories_id_seq OWNED BY public.trade_barriers_jurisdiction_histories.id;


--
-- Name: trade_barriers_themes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trade_barriers_themes (
    id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: trade_barriers_themes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trade_barriers_themes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trade_barriers_themes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trade_barriers_themes_id_seq OWNED BY public.trade_barriers_themes.id;


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
    remember_created_at timestamp(6) without time zone,
    reset_password_sent_at timestamp(6) without time zone,
    reset_password_token character varying,
    sign_in_count integer DEFAULT 0 NOT NULL,
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
-- Name: agent_runs; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.agent_runs (
    id bigint NOT NULL,
    agent_name character varying NOT NULL,
    agent_version character varying,
    input_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying DEFAULT 'running'::character varying NOT NULL,
    started_at timestamp(6) without time zone NOT NULL,
    finished_at timestamp(6) without time zone,
    triggered_by character varying,
    report text,
    summary jsonb,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT agent_runs_status_check CHECK (((status)::text = ANY (ARRAY[('running'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: agent_runs_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.agent_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agent_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.agent_runs_id_seq OWNED BY warehouse.agent_runs.id;


--
-- Name: api_tokens; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.api_tokens (
    id bigint NOT NULL,
    name character varying NOT NULL,
    token_hash character varying NOT NULL,
    scopes character varying[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    last_used_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: api_tokens_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.api_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.api_tokens_id_seq OWNED BY warehouse.api_tokens.id;


--
-- Name: canonical_observations; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.canonical_observations (
    id bigint NOT NULL,
    extracted_observation_id bigint NOT NULL,
    measure_id bigint NOT NULL,
    document_id bigint NOT NULL,
    reporting_organization_id bigint,
    responsible_organization_id bigint,
    observed_organization_id bigint,
    geo_boundary_id bigint,
    jurisdiction_id bigint,
    measurement_year integer NOT NULL,
    period_start date,
    period_end date,
    period_type character varying,
    value_type character varying NOT NULL,
    period_basis character varying DEFAULT 'full_year'::character varying NOT NULL,
    value_numeric double precision,
    value_text text,
    unit_id bigint,
    vintage_date date,
    status character varying DEFAULT 'reported'::character varying NOT NULL,
    is_total boolean DEFAULT false NOT NULL,
    is_residual boolean DEFAULT false NOT NULL,
    approved_by character varying,
    approved_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    metric_version_id bigint,
    composition_id bigint,
    component_id bigint,
    CONSTRAINT canonical_observations_period_basis_check CHECK (((period_basis)::text = ANY (ARRAY[('full_year'::character varying)::text, ('ytd_q1'::character varying)::text, ('ytd_q2'::character varying)::text, ('ytd_q3'::character varying)::text, ('as_of_date'::character varying)::text, ('month'::character varying)::text, ('quarter'::character varying)::text]))),
    CONSTRAINT canonical_observations_status_check CHECK (((status)::text = ANY (ARRAY[('reported'::character varying)::text, ('estimated'::character varying)::text, ('revised'::character varying)::text, ('final'::character varying)::text]))),
    CONSTRAINT canonical_observations_value_type_check CHECK (((value_type)::text = ANY (ARRAY[('actual'::character varying)::text, ('target'::character varying)::text, ('projected'::character varying)::text, ('plan'::character varying)::text, ('budget'::character varying)::text])))
);


--
-- Name: canonical_observations_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.canonical_observations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: canonical_observations_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.canonical_observations_id_seq OWNED BY warehouse.canonical_observations.id;


--
-- Name: composition_validation_results; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.composition_validation_results (
    id bigint NOT NULL,
    measure_id bigint NOT NULL,
    composition_id bigint NOT NULL,
    observed_organization_id bigint,
    geo_boundary_id bigint,
    period_start date,
    period_end date,
    measurement_year integer,
    validation_type character varying NOT NULL,
    status character varying NOT NULL,
    expected_value numeric,
    actual_value numeric,
    difference numeric,
    severity character varying,
    message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT cvr_severity_check CHECK (((severity IS NULL) OR ((severity)::text = ANY (ARRAY[('low'::character varying)::text, ('medium'::character varying)::text, ('high'::character varying)::text, ('critical'::character varying)::text])))),
    CONSTRAINT cvr_status_check CHECK (((status)::text = ANY (ARRAY[('ok'::character varying)::text, ('warn'::character varying)::text, ('fail'::character varying)::text])))
);


--
-- Name: composition_validation_results_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.composition_validation_results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: composition_validation_results_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.composition_validation_results_id_seq OWNED BY warehouse.composition_validation_results.id;


--
-- Name: crosswalk_metric_compatibility; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.crosswalk_metric_compatibility (
    id bigint NOT NULL,
    crosswalk_set_id bigint NOT NULL,
    measure_id bigint NOT NULL,
    compatibility character varying NOT NULL,
    reason text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT cmc_compatibility_check CHECK (((compatibility)::text = ANY (ARRAY[('recommended'::character varying)::text, ('acceptable'::character varying)::text, ('risky'::character varying)::text, ('not_allowed'::character varying)::text])))
);


--
-- Name: crosswalk_metric_compatibility_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.crosswalk_metric_compatibility_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: crosswalk_metric_compatibility_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.crosswalk_metric_compatibility_id_seq OWNED BY warehouse.crosswalk_metric_compatibility.id;


--
-- Name: geography_crosswalk_entries; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.geography_crosswalk_entries (
    id bigint NOT NULL,
    crosswalk_set_id bigint NOT NULL,
    from_geo_id bigint NOT NULL,
    to_geo_id bigint NOT NULL,
    weight numeric NOT NULL,
    weight_numerator numeric,
    weight_denominator numeric,
    confidence numeric,
    relationship_type character varying NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT crosswalk_entries_confidence_range CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))),
    CONSTRAINT crosswalk_entries_relationship_kind_check CHECK (((relationship_type)::text = ANY (ARRAY[('equivalent'::character varying)::text, ('contains'::character varying)::text, ('contained_by'::character varying)::text, ('split'::character varying)::text, ('merged'::character varying)::text, ('overlaps'::character varying)::text, ('allocated'::character varying)::text, ('estimated'::character varying)::text, ('manual'::character varying)::text]))),
    CONSTRAINT crosswalk_entries_weight_range CHECK (((weight >= (0)::numeric) AND (weight <= (1)::numeric)))
);


--
-- Name: crosswalk_weight_checks; Type: VIEW; Schema: warehouse; Owner: -
--

CREATE VIEW warehouse.crosswalk_weight_checks AS
 SELECT crosswalk_set_id,
    from_geo_id,
    sum(weight) AS total_weight,
    count(*) AS target_count
   FROM warehouse.geography_crosswalk_entries
  GROUP BY crosswalk_set_id, from_geo_id;


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
    updated_at timestamp(6) without time zone NOT NULL,
    code_system character varying NOT NULL,
    valid_from date,
    valid_to date,
    CONSTRAINT geo_boundaries_valid_range CHECK (((valid_to IS NULL) OR (valid_from IS NULL) OR (valid_to >= valid_from)))
);


--
-- Name: jurisdictions; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.jurisdictions (
    id bigint NOT NULL,
    name character varying NOT NULL,
    code character varying NOT NULL,
    level character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    slug character varying NOT NULL,
    fiscal_year_start_month integer NOT NULL,
    default_currency character varying DEFAULT 'CAD'::character varying NOT NULL,
    region_code character varying,
    CONSTRAINT jurisdictions_fiscal_year_start_month_check CHECK (((fiscal_year_start_month >= 1) AND (fiscal_year_start_month <= 12))),
    CONSTRAINT jurisdictions_level_check CHECK (((level)::text = ANY (ARRAY['municipal'::text, 'regional'::text, 'provincial'::text, 'territorial'::text, 'federal'::text, 'crown_corp'::text, 'authority'::text, 'national'::text, 'supranational'::text])))
);


--
-- Name: kpi_documents; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.kpi_documents (
    id bigint NOT NULL,
    jurisdiction_id bigint NOT NULL,
    organization_id bigint,
    raw_ingestion_id bigint,
    fiscal_year integer NOT NULL,
    published_at date,
    published_at_source character varying,
    source_page_url character varying,
    doc_url character varying NOT NULL,
    doc_title character varying,
    doc_type character varying,
    filepath character varying,
    content_hash character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    agent_run_id bigint,
    CONSTRAINT kpi_documents_published_at_source_check CHECK (((published_at_source IS NULL) OR ((published_at_source)::text = ANY (ARRAY[('pdf_metadata'::character varying)::text, ('http_last_modified'::character varying)::text, ('council_schedule'::character varying)::text, ('discovered_at_fallback'::character varying)::text, ('manual'::character varying)::text]))))
);


--
-- Name: measures; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.measures (
    id bigint NOT NULL,
    organization_id bigint,
    slug character varying NOT NULL,
    canonical_name character varying NOT NULL,
    unit_id bigint NOT NULL,
    service_category character varying,
    description text,
    first_seen_year integer,
    last_seen_year integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    agent_run_id bigint,
    aggregation_type character varying DEFAULT 'unknown'::character varying NOT NULL,
    numerator_measure_id bigint,
    denominator_measure_id bigint,
    higher_is_bad boolean,
    frequency character varying,
    category character varying,
    search_revision integer DEFAULT 0 NOT NULL,
    search_index_sequence bigint,
    search_synced_at timestamp with time zone,
    search_content_hash character varying,
    search_embedding_model character varying,
    search_embedding_input_hash character varying,
    search_embedding_scope character varying,
    search_embedding_input_tokens integer,
    CONSTRAINT measures_aggregation_type_check CHECK (((aggregation_type)::text = ANY (ARRAY[('additive'::character varying)::text, ('semi_additive'::character varying)::text, ('average'::character varying)::text, ('ratio'::character varying)::text, ('median'::character varying)::text, ('index'::character varying)::text, ('rate'::character varying)::text, ('part_of_whole'::character varying)::text, ('non_aggregable'::character varying)::text, ('unknown'::character varying)::text]))),
    CONSTRAINT measures_frequency_check CHECK (((frequency IS NULL) OR ((frequency)::text = ANY (ARRAY[('annual'::character varying)::text, ('fiscal_year'::character varying)::text, ('quarterly'::character varying)::text, ('monthly'::character varying)::text, ('point_in_time'::character varying)::text, ('irregular'::character varying)::text, ('unknown'::character varying)::text])))),
    CONSTRAINT measures_no_self_ratio CHECK ((((numerator_measure_id IS NULL) OR (numerator_measure_id <> id)) AND ((denominator_measure_id IS NULL) OR (denominator_measure_id <> id)))),
    CONSTRAINT measures_ratio_has_components CHECK ((((aggregation_type)::text <> ALL (ARRAY[('ratio'::character varying)::text, ('rate'::character varying)::text])) OR ((numerator_measure_id IS NOT NULL) AND (denominator_measure_id IS NOT NULL)) OR ((aggregation_type)::text = 'unknown'::text)))
);


--
-- Name: organizations; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.organizations (
    id bigint NOT NULL,
    canonical_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    needs_review boolean DEFAULT false NOT NULL,
    org_id_infobase integer,
    updated_at timestamp(6) without time zone NOT NULL,
    jurisdiction_id bigint NOT NULL,
    slug character varying NOT NULL,
    kind character varying,
    parent_organization_id bigint,
    active_from_year integer,
    active_to_year integer,
    description text
);


--
-- Name: units; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.units (
    id bigint NOT NULL,
    symbol character varying NOT NULL,
    kind character varying NOT NULL,
    base_unit character varying,
    scale double precision DEFAULT 1.0 NOT NULL,
    currency_code character varying,
    denominator_unit character varying,
    denominator_scale double precision,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT units_base_unit_check CHECK (((base_unit IS NULL) OR ((base_unit)::text = ANY (ARRAY[('ratio'::character varying)::text, ('count'::character varying)::text, ('dollars'::character varying)::text, ('seconds'::character varying)::text, ('minutes'::character varying)::text, ('hours'::character varying)::text, ('days'::character varying)::text, ('meters'::character varying)::text, ('kilometers'::character varying)::text, ('square_meters'::character varying)::text, ('hectares'::character varying)::text, ('tonnes'::character varying)::text, ('kwh'::character varying)::text, ('mwh'::character varying)::text, ('tco2e'::character varying)::text, ('other'::character varying)::text])))),
    CONSTRAINT units_kind_check CHECK (((kind)::text = ANY (ARRAY[('absolute'::character varying)::text, ('ratio'::character varying)::text, ('rate'::character varying)::text, ('qualitative'::character varying)::text]))),
    CONSTRAINT units_qualitative_has_no_base CHECK ((((kind)::text = 'qualitative'::text) = (base_unit IS NULL))),
    CONSTRAINT units_rate_has_denominator CHECK ((((kind)::text = 'rate'::text) = (denominator_unit IS NOT NULL)))
);


--
-- Name: dashboard_observations; Type: VIEW; Schema: warehouse; Owner: -
--

CREATE VIEW warehouse.dashboard_observations AS
 SELECT co.id AS canonical_observation_id,
    co.extracted_observation_id,
    co.measure_id,
    m.slug AS measure_slug,
    m.canonical_name AS measure_name,
    m.category AS measure_category,
    m.aggregation_type,
    co.metric_version_id,
    co.composition_id,
    co.component_id,
    co.measurement_year,
    co.period_start,
    co.period_end,
    co.period_type,
    co.value_type,
    co.period_basis,
    co.value_numeric,
    co.value_text,
    co.unit_id,
    u.symbol AS unit_symbol,
    co.status,
    co.vintage_date,
    co.is_total,
    co.is_residual,
    co.observed_organization_id,
    oo.slug AS observed_organization_slug,
    oo.canonical_name AS observed_organization_name,
    co.responsible_organization_id,
    co.reporting_organization_id,
    co.jurisdiction_id,
    j.slug AS jurisdiction_slug,
    j.name AS jurisdiction_name,
    co.geo_boundary_id,
    gb.geo_uid,
    gb.boundary_type,
    gb.code_system AS geo_code_system,
    co.document_id,
    d.doc_url,
    d.doc_title,
    d.fiscal_year AS document_fiscal_year,
    d.published_at AS document_published_at,
    co.approved_at,
    co.approved_by
   FROM ((((((warehouse.canonical_observations co
     JOIN warehouse.measures m ON ((m.id = co.measure_id)))
     LEFT JOIN warehouse.units u ON ((u.id = co.unit_id)))
     LEFT JOIN warehouse.organizations oo ON ((oo.id = co.observed_organization_id)))
     LEFT JOIN warehouse.jurisdictions j ON ((j.id = co.jurisdiction_id)))
     LEFT JOIN warehouse.geo_boundaries gb ON ((gb.id = co.geo_boundary_id)))
     LEFT JOIN warehouse.kpi_documents d ON ((d.id = co.document_id)));


--
-- Name: derived_observations; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.derived_observations (
    id bigint NOT NULL,
    measure_id bigint NOT NULL,
    from_canonical_observation_id bigint,
    crosswalk_set_id bigint,
    original_geo_id bigint,
    derived_geo_id bigint,
    measurement_year integer NOT NULL,
    period_start date,
    period_end date,
    period_type character varying,
    value_numeric double precision,
    value_text text,
    unit_id bigint,
    derivation_method character varying NOT NULL,
    confidence numeric,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT derived_observations_confidence_range CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))),
    CONSTRAINT derived_observations_method_check CHECK (((derivation_method)::text = ANY (ARRAY[('crosswalk_allocation'::character varying)::text, ('aggregation'::character varying)::text, ('ratio_recompute'::character varying)::text, ('definition_normalization'::character varying)::text, ('rebase'::character varying)::text, ('manual'::character varying)::text])))
);


--
-- Name: derived_observations_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.derived_observations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: derived_observations_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.derived_observations_id_seq OWNED BY warehouse.derived_observations.id;


--
-- Name: election_candidates; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.election_candidates (
    id bigint NOT NULL,
    election_race_id bigint NOT NULL,
    full_name character varying NOT NULL,
    first_name character varying,
    last_name character varying,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    nomination_date date,
    withdrawn_date date,
    email character varying,
    phone character varying,
    website character varying,
    social_links jsonb DEFAULT '[]'::jsonb NOT NULL,
    last_seen_at timestamp with time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    photo_source character varying,
    photo_attribution character varying,
    photo_suggestions jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT election_candidates_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'withdrawn'::character varying])::text[])))
);


--
-- Name: election_candidates_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.election_candidates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: election_candidates_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.election_candidates_id_seq OWNED BY warehouse.election_candidates.id;


--
-- Name: election_races; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.election_races (
    id bigint NOT NULL,
    election_id bigint NOT NULL,
    office_type character varying NOT NULL,
    district_type character varying DEFAULT 'at_large'::character varying NOT NULL,
    district_number integer,
    district_name character varying,
    office_body character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT election_races_district_type_check CHECK (((district_type)::text = ANY ((ARRAY['at_large'::character varying, 'ward'::character varying, 'school_board_ward'::character varying, 'riding'::character varying, 'district'::character varying])::text[]))),
    CONSTRAINT election_races_office_type_check CHECK (((office_type)::text = ANY ((ARRAY['mayor'::character varying, 'councillor'::character varying, 'trustee'::character varying, 'mp'::character varying, 'mpp'::character varying])::text[])))
);


--
-- Name: election_races_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.election_races_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: election_races_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.election_races_id_seq OWNED BY warehouse.election_races.id;


--
-- Name: elections; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.elections (
    id bigint NOT NULL,
    jurisdiction_id bigint NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    kind character varying DEFAULT 'municipal'::character varying NOT NULL,
    election_date date NOT NULL,
    nomination_close_date date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    published_at timestamp(6) without time zone,
    CONSTRAINT elections_kind_check CHECK (((kind)::text = ANY ((ARRAY['municipal'::character varying, 'provincial'::character varying, 'federal'::character varying, 'by_election'::character varying])::text[])))
);


--
-- Name: elections_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.elections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: elections_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.elections_id_seq OWNED BY warehouse.elections.id;


--
-- Name: extracted_observations; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.extracted_observations (
    id bigint NOT NULL,
    measure_id bigint NOT NULL,
    measurement_year integer NOT NULL,
    value_type character varying NOT NULL,
    value_numeric double precision,
    value_text text,
    value_raw text,
    period_basis character varying DEFAULT 'full_year'::character varying NOT NULL,
    document_id bigint NOT NULL,
    source_page integer,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    agent_run_id bigint,
    reporting_organization_id bigint,
    responsible_organization_id bigint,
    observed_organization_id bigint,
    reporting_organization_raw character varying,
    responsible_organization_raw character varying,
    observed_organization_raw character varying,
    geo_boundary_id bigint,
    jurisdiction_id bigint,
    geography_name_raw character varying,
    jurisdiction_name_raw character varying,
    metric_name_raw character varying,
    period_label_raw character varying,
    unit_raw character varying,
    period_start date,
    period_end date,
    period_type character varying,
    source_section character varying,
    source_table character varying,
    source_chart character varying,
    evidence_quote text,
    extraction_confidence numeric,
    needs_review boolean DEFAULT false NOT NULL,
    review_status character varying DEFAULT 'pending'::character varying NOT NULL,
    metric_version_id bigint,
    composition_id bigint,
    component_id bigint,
    CONSTRAINT extracted_observations_confidence_range CHECK (((extraction_confidence IS NULL) OR ((extraction_confidence >= (0)::numeric) AND (extraction_confidence <= (1)::numeric)))),
    CONSTRAINT extracted_observations_period_basis_check CHECK (((period_basis)::text = ANY (ARRAY[('full_year'::character varying)::text, ('ytd_q1'::character varying)::text, ('ytd_q2'::character varying)::text, ('ytd_q3'::character varying)::text, ('as_of_date'::character varying)::text, ('month'::character varying)::text, ('quarter'::character varying)::text]))),
    CONSTRAINT extracted_observations_review_status_check CHECK (((review_status)::text = ANY (ARRAY[('pending'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text, ('superseded'::character varying)::text]))),
    CONSTRAINT extracted_observations_value_type_check CHECK (((value_type)::text = ANY (ARRAY[('actual'::character varying)::text, ('target'::character varying)::text, ('projected'::character varying)::text, ('plan'::character varying)::text, ('budget'::character varying)::text])))
);


--
-- Name: extraction_assertions; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.extraction_assertions (
    id bigint NOT NULL,
    extracted_observation_id bigint NOT NULL,
    assertion_type character varying NOT NULL,
    assertion_text text NOT NULL,
    confidence numeric,
    evidence_quote text,
    source_page integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT extraction_assertions_confidence_range CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))))
);


--
-- Name: extraction_assertions_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.extraction_assertions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extraction_assertions_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.extraction_assertions_id_seq OWNED BY warehouse.extraction_assertions.id;


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
    vote_type character varying NOT NULL,
    search_revision integer DEFAULT 0 NOT NULL,
    search_index_sequence bigint,
    search_synced_at timestamp with time zone,
    search_content_hash character varying,
    search_embedding_model character varying,
    search_embedding_input_hash character varying,
    search_embedding_scope character varying,
    search_embedding_input_tokens integer
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
-- Name: geography_crosswalk_entries_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.geography_crosswalk_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: geography_crosswalk_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.geography_crosswalk_entries_id_seq OWNED BY warehouse.geography_crosswalk_entries.id;


--
-- Name: geography_crosswalk_sets; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.geography_crosswalk_sets (
    id bigint NOT NULL,
    name character varying NOT NULL,
    description text,
    from_code_system character varying NOT NULL,
    to_code_system character varying NOT NULL,
    from_geo_type character varying,
    to_geo_type character varying,
    method character varying NOT NULL,
    weight_basis character varying NOT NULL,
    expected_weight_sum numeric DEFAULT 1.0 NOT NULL,
    allow_partial_coverage boolean DEFAULT false NOT NULL,
    source_id bigint,
    valid_from date,
    valid_to date,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT crosswalk_sets_valid_range CHECK (((valid_to IS NULL) OR (valid_from IS NULL) OR (valid_to >= valid_from))),
    CONSTRAINT crosswalk_sets_weight_basis_check CHECK (((weight_basis)::text = ANY (ARRAY[('area'::character varying)::text, ('population'::character varying)::text, ('dwellings'::character varying)::text, ('households'::character varying)::text, ('business_count'::character varying)::text, ('employment'::character varying)::text, ('road_length'::character varying)::text, ('property_assessment'::character varying)::text, ('manual'::character varying)::text, ('exact_containment'::character varying)::text, ('unknown'::character varying)::text])))
);


--
-- Name: geography_crosswalk_sets_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.geography_crosswalk_sets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: geography_crosswalk_sets_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.geography_crosswalk_sets_id_seq OWNED BY warehouse.geography_crosswalk_sets.id;


--
-- Name: human_review_queue; Type: VIEW; Schema: warehouse; Owner: -
--

CREATE VIEW warehouse.human_review_queue AS
SELECT
    NULL::bigint AS extracted_observation_id,
    NULL::bigint AS measure_id,
    NULL::bigint AS document_id,
    NULL::bigint AS agent_run_id,
    NULL::integer AS measurement_year,
    NULL::character varying AS value_type,
    NULL::character varying AS period_basis,
    NULL::double precision AS value_numeric,
    NULL::text AS value_text,
    NULL::text AS value_raw,
    NULL::character varying AS unit_raw,
    NULL::character varying AS metric_name_raw,
    NULL::character varying AS geography_name_raw,
    NULL::character varying AS jurisdiction_name_raw,
    NULL::character varying AS reporting_organization_raw,
    NULL::character varying AS responsible_organization_raw,
    NULL::character varying AS observed_organization_raw,
    NULL::text AS evidence_quote,
    NULL::integer AS source_page,
    NULL::character varying AS source_section,
    NULL::character varying AS source_table,
    NULL::numeric AS extraction_confidence,
    NULL::boolean AS needs_review,
    NULL::character varying AS review_status,
    NULL::timestamp(6) without time zone AS created_at,
    NULL::bigint AS open_flag_count,
    NULL::integer AS highest_open_severity_rank,
    NULL::character varying AS highest_open_severity,
    NULL::boolean AS has_open_flags;


--
-- Name: jurisdictions_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.jurisdictions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jurisdictions_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.jurisdictions_id_seq OWNED BY warehouse.jurisdictions.id;


--
-- Name: kpi_documents_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.kpi_documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: kpi_documents_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.kpi_documents_id_seq OWNED BY warehouse.kpi_documents.id;


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
-- Name: measure_citations_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.measure_citations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: measure_citations_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.measure_citations_id_seq OWNED BY warehouse.extracted_observations.id;


--
-- Name: measure_facts; Type: VIEW; Schema: warehouse; Owner: -
--

CREATE VIEW warehouse.measure_facts AS
 SELECT id AS canonical_observation_id,
    measure_id,
    measurement_year,
    value_type,
    period_basis,
    period_start,
    period_end,
    period_type,
    value_numeric,
    value_text,
    document_id,
    extracted_observation_id,
    observed_organization_id,
    geo_boundary_id,
    jurisdiction_id,
    status,
    vintage_date,
    approved_at
   FROM ( SELECT c.id,
            c.extracted_observation_id,
            c.measure_id,
            c.document_id,
            c.observed_organization_id,
            c.geo_boundary_id,
            c.jurisdiction_id,
            c.measurement_year,
            c.value_type,
            c.period_basis,
            c.period_start,
            c.period_end,
            c.period_type,
            c.value_numeric,
            c.value_text,
            c.vintage_date,
            c.status,
            c.approved_at,
            row_number() OVER (PARTITION BY c.measure_id, c.measurement_year, c.value_type, c.period_basis, c.period_start, c.observed_organization_id, c.geo_boundary_id, c.jurisdiction_id ORDER BY c.vintage_date DESC NULLS LAST, c.approved_at DESC, c.id DESC) AS rn
           FROM warehouse.canonical_observations c) co
  WHERE (rn = 1);


--
-- Name: measure_footnotes; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.measure_footnotes (
    measure_id bigint NOT NULL,
    source_footnote_id bigint NOT NULL,
    created_at timestamp(6) without time zone DEFAULT now() NOT NULL
);


--
-- Name: measure_lineages; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.measure_lineages (
    id bigint NOT NULL,
    predecessor_id bigint NOT NULL,
    successor_id bigint NOT NULL,
    transition_year integer NOT NULL,
    transition_kind character varying NOT NULL,
    acknowledged_in_document_id bigint,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT measure_lineages_distinct CHECK ((predecessor_id <> successor_id)),
    CONSTRAINT measure_lineages_kind_check CHECK (((transition_kind)::text = ANY (ARRAY[('rename'::character varying)::text, ('methodology_revision'::character varying)::text, ('split'::character varying)::text, ('merge'::character varying)::text, ('unit_change'::character varying)::text, ('scope_change'::character varying)::text, ('revived'::character varying)::text])))
);


--
-- Name: measure_lineages_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.measure_lineages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: measure_lineages_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.measure_lineages_id_seq OWNED BY warehouse.measure_lineages.id;


--
-- Name: measures_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.measures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: measures_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.measures_id_seq OWNED BY warehouse.measures.id;


--
-- Name: media_articles; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.media_articles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    media_feed_id bigint,
    external_key character varying,
    state character varying DEFAULT 'draft'::character varying NOT NULL,
    visibility character varying DEFAULT 'public'::character varying NOT NULL,
    permission_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    search_revision integer DEFAULT 0 NOT NULL,
    search_index_sequence bigint,
    search_synced_at timestamp with time zone,
    canonical_url text,
    canonical_url_digest character varying,
    source_url text,
    title text,
    summary text,
    content text,
    language character varying DEFAULT 'und'::character varying NOT NULL,
    published_at timestamp with time zone,
    source_updated_at timestamp with time zone,
    first_seen_at timestamp with time zone,
    last_seen_at timestamp with time zone,
    search_content_hash character varying,
    ontology jsonb DEFAULT '{}'::jsonb NOT NULL,
    realm_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    search_embedding_model character varying,
    search_embedding_input_hash character varying,
    search_embedding_scope character varying,
    search_embedding_input_tokens integer,
    extraction_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    validation_errors jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT media_articles_embedding_scope CHECK (((search_embedding_scope IS NULL) OR ((search_embedding_scope)::text = ANY ((ARRAY['full'::character varying, 'truncated'::character varying])::text[])))),
    CONSTRAINT media_articles_revision_nonnegative CHECK ((search_revision >= 0)),
    CONSTRAINT media_articles_state CHECK (((state)::text = ANY ((ARRAY['draft'::character varying, 'published'::character varying, 'withdrawn'::character varying, 'invalid'::character varying])::text[])))
);


--
-- Name: media_feed_fetches; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.media_feed_fetches (
    id bigint NOT NULL,
    media_feed_id bigint NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    http_status integer,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    duration_ms integer,
    items_discovered integer DEFAULT 0 NOT NULL,
    response_checksum character varying,
    error text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT media_feed_fetches_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying, 'succeeded'::character varying, 'failed'::character varying, 'not_modified'::character varying])::text[])))
);


--
-- Name: media_feed_fetches_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.media_feed_fetches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: media_feed_fetches_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.media_feed_fetches_id_seq OWNED BY warehouse.media_feed_fetches.id;


--
-- Name: media_feeds; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.media_feeds (
    id bigint NOT NULL,
    name character varying NOT NULL,
    strategy character varying NOT NULL,
    url text,
    cadence_seconds integer DEFAULT 300 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    next_fetch_at timestamp with time zone,
    etag character varying,
    last_modified character varying,
    last_succeeded_at timestamp with time zone,
    last_failed_at timestamp with time zone,
    consecutive_failures integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    publisher_name character varying NOT NULL,
    publisher_domain character varying NOT NULL,
    language character varying DEFAULT 'en'::character varying NOT NULL,
    fallback_url text,
    allow_http boolean DEFAULT false NOT NULL,
    CONSTRAINT media_feeds_cadence_minimum CHECK ((cadence_seconds >= 60)),
    CONSTRAINT media_feeds_failures_nonnegative CHECK ((consecutive_failures >= 0))
);


--
-- Name: media_feeds_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.media_feeds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: media_feeds_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.media_feeds_id_seq OWNED BY warehouse.media_feeds.id;


--
-- Name: metric_aliases; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.metric_aliases (
    id bigint NOT NULL,
    measure_id bigint NOT NULL,
    alias_text character varying NOT NULL,
    kind character varying DEFAULT 'raw_text'::character varying NOT NULL,
    source_id bigint,
    document_id bigint,
    canonical_measure_id bigint,
    valid_from date,
    valid_to date,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT metric_aliases_equivalence_target CHECK ((((kind)::text <> 'measure_equivalence'::text) OR ((canonical_measure_id IS NOT NULL) AND (canonical_measure_id <> measure_id)))),
    CONSTRAINT metric_aliases_kind_check CHECK (((kind)::text = ANY (ARRAY[('raw_text'::character varying)::text, ('measure_equivalence'::character varying)::text])))
);


--
-- Name: metric_aliases_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.metric_aliases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_aliases_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.metric_aliases_id_seq OWNED BY warehouse.metric_aliases.id;


--
-- Name: metric_component_relationships; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.metric_component_relationships (
    id bigint NOT NULL,
    from_component_id bigint NOT NULL,
    to_component_id bigint NOT NULL,
    relationship_type character varying NOT NULL,
    valid_from date,
    valid_to date,
    source_id bigint,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT mcr_distinct CHECK ((from_component_id <> to_component_id)),
    CONSTRAINT mcr_relationship_kind_check CHECK (((relationship_type)::text = ANY (ARRAY[('renamed_to'::character varying)::text, ('split_into'::character varying)::text, ('merged_into'::character varying)::text, ('reclassified_as'::character varying)::text, ('equivalent_to'::character varying)::text, ('parent_of'::character varying)::text, ('child_of'::character varying)::text])))
);


--
-- Name: metric_component_relationships_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.metric_component_relationships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_component_relationships_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.metric_component_relationships_id_seq OWNED BY warehouse.metric_component_relationships.id;


--
-- Name: metric_components; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.metric_components (
    id bigint NOT NULL,
    measure_id bigint NOT NULL,
    composition_id bigint,
    component_type character varying NOT NULL,
    component_code character varying,
    component_name character varying NOT NULL,
    parent_component_id bigint,
    valid_from date,
    valid_to date,
    sort_order integer,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metric_components_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.metric_components_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_components_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.metric_components_id_seq OWNED BY warehouse.metric_components.id;


--
-- Name: metric_compositions; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.metric_compositions (
    id bigint NOT NULL,
    measure_id bigint NOT NULL,
    composition_type character varying NOT NULL,
    name character varying NOT NULL,
    expected_total numeric,
    expected_total_unit_id bigint,
    allow_other boolean DEFAULT true NOT NULL,
    allow_unknown boolean DEFAULT true NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metric_compositions_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.metric_compositions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_compositions_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.metric_compositions_id_seq OWNED BY warehouse.metric_compositions.id;


--
-- Name: metric_versions; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.metric_versions (
    id bigint NOT NULL,
    measure_id bigint NOT NULL,
    version_label character varying NOT NULL,
    definition text NOT NULL,
    methodology text,
    active_from date,
    active_to date,
    source_id bigint,
    document_id bigint,
    breaking_change boolean DEFAULT false NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT metric_versions_active_range CHECK (((active_to IS NULL) OR (active_from IS NULL) OR (active_to >= active_from)))
);


--
-- Name: metric_versions_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.metric_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metric_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.metric_versions_id_seq OWNED BY warehouse.metric_versions.id;


--
-- Name: observation_footnotes; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.observation_footnotes (
    extracted_observation_id bigint NOT NULL,
    source_footnote_id bigint NOT NULL,
    created_at timestamp(6) without time zone DEFAULT now() NOT NULL
);


--
-- Name: observation_review_flags; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.observation_review_flags (
    id bigint NOT NULL,
    extracted_observation_id bigint NOT NULL,
    flag_type character varying NOT NULL,
    severity character varying DEFAULT 'medium'::character varying NOT NULL,
    message text NOT NULL,
    evidence text,
    resolved_at timestamp with time zone,
    resolved_by character varying,
    resolution_notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT observation_review_flags_resolved_pair CHECK (((resolved_at IS NULL) = (resolved_by IS NULL))),
    CONSTRAINT observation_review_flags_severity_check CHECK (((severity)::text = ANY (ARRAY[('low'::character varying)::text, ('medium'::character varying)::text, ('high'::character varying)::text, ('critical'::character varying)::text])))
);


--
-- Name: observation_review_flags_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.observation_review_flags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observation_review_flags_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.observation_review_flags_id_seq OWNED BY warehouse.observation_review_flags.id;


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
-- Name: organization_lineages; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.organization_lineages (
    id bigint NOT NULL,
    predecessor_id bigint NOT NULL,
    successor_id bigint NOT NULL,
    transition_year integer NOT NULL,
    transition_kind character varying NOT NULL,
    acknowledged_in_document_id bigint,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT organization_lineages_distinct CHECK ((predecessor_id <> successor_id)),
    CONSTRAINT organization_lineages_kind_check CHECK (((transition_kind)::text = ANY (ARRAY[('rename'::character varying)::text, ('merge'::character varying)::text, ('split'::character varying)::text, ('absorb'::character varying)::text, ('spin_off'::character varying)::text, ('revived'::character varying)::text])))
);


--
-- Name: organization_lineages_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.organization_lineages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organization_lineages_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.organization_lineages_id_seq OWNED BY warehouse.organization_lineages.id;


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
-- Name: pledges_to_vote; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.pledges_to_vote (
    id bigint NOT NULL,
    election_id bigint NOT NULL,
    subscriber_id bigint NOT NULL,
    region character varying NOT NULL,
    pledged_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    share_token character varying NOT NULL
);


--
-- Name: pledges_to_vote_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.pledges_to_vote_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pledges_to_vote_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.pledges_to_vote_id_seq OWNED BY warehouse.pledges_to_vote.id;


--
-- Name: postal_codes; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.postal_codes (
    id bigint NOT NULL,
    postal_code character varying(7) NOT NULL,
    city character varying,
    province_code character varying(2),
    time_zone_offset integer,
    latitude numeric(10,7) NOT NULL,
    longitude numeric(11,7) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: postal_codes_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.postal_codes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: postal_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.postal_codes_id_seq OWNED BY warehouse.postal_codes.id;


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
-- Name: review_decisions; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.review_decisions (
    id bigint NOT NULL,
    extracted_observation_id bigint NOT NULL,
    reviewer character varying NOT NULL,
    decision character varying NOT NULL,
    previous_value jsonb,
    new_value jsonb,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT review_decisions_decision_check CHECK (((decision)::text = ANY (ARRAY[('approved'::character varying)::text, ('rejected'::character varying)::text, ('edited'::character varying)::text, ('needs_more_info'::character varying)::text])))
);


--
-- Name: review_decisions_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.review_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: review_decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.review_decisions_id_seq OWNED BY warehouse.review_decisions.id;


--
-- Name: source_footnotes; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.source_footnotes (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    agent_run_id bigint,
    page integer,
    marker character varying,
    footnote_text text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: source_footnotes_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.source_footnotes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_footnotes_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.source_footnotes_id_seq OWNED BY warehouse.source_footnotes.id;


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
    url character varying NOT NULL,
    license character varying,
    attribution character varying
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
-- Name: spending_awards; Type: TABLE; Schema: warehouse; Owner: -
--

CREATE TABLE warehouse.spending_awards (
    id bigint NOT NULL,
    source_id bigint NOT NULL,
    raw_ingestion_id bigint,
    payer_organization_id bigint,
    external_key character varying NOT NULL,
    award_type character varying NOT NULL,
    state character varying DEFAULT 'published'::character varying NOT NULL,
    language character varying DEFAULT 'en'::character varying NOT NULL,
    title text NOT NULL,
    description text,
    payer_name character varying,
    recipient_name character varying,
    recipient_type character varying,
    program_name character varying,
    program_key character varying,
    fiscal_year integer,
    occurred_at timestamp with time zone,
    amount numeric(20,2),
    currency character varying DEFAULT 'CAD'::character varying NOT NULL,
    is_aggregated boolean DEFAULT false NOT NULL,
    source_url character varying,
    province_code character varying,
    country_code character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    first_seen_at timestamp with time zone NOT NULL,
    last_seen_at timestamp with time zone NOT NULL,
    search_revision integer DEFAULT 0 NOT NULL,
    search_index_sequence bigint,
    search_synced_at timestamp with time zone,
    search_content_hash character varying,
    search_embedding_model character varying,
    search_embedding_input_hash character varying,
    search_embedding_scope character varying,
    search_embedding_input_tokens integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    canonical_key character varying NOT NULL,
    is_canonical boolean DEFAULT true NOT NULL,
    CONSTRAINT spending_awards_award_type CHECK (((award_type)::text = ANY ((ARRAY['contract'::character varying, 'grant'::character varying, 'contribution'::character varying, 'transfer_payment'::character varying])::text[]))),
    CONSTRAINT spending_awards_revision_nonnegative CHECK ((search_revision >= 0)),
    CONSTRAINT spending_awards_state CHECK (((state)::text = ANY ((ARRAY['published'::character varying, 'withdrawn'::character varying])::text[])))
);


--
-- Name: spending_awards_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.spending_awards_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: spending_awards_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.spending_awards_id_seq OWNED BY warehouse.spending_awards.id;


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
    updated_at timestamp(6) without time zone NOT NULL,
    search_revision integer DEFAULT 0 NOT NULL,
    search_index_sequence bigint,
    search_synced_at timestamp with time zone,
    search_content_hash character varying,
    search_embedding_model character varying,
    search_embedding_input_hash character varying,
    search_embedding_scope character varying,
    search_embedding_input_tokens integer
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
-- Name: units_id_seq; Type: SEQUENCE; Schema: warehouse; Owner: -
--

CREATE SEQUENCE warehouse.units_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: units_id_seq; Type: SEQUENCE OWNED BY; Schema: warehouse; Owner: -
--

ALTER SEQUENCE warehouse.units_id_seq OWNED BY warehouse.units.id;


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
-- Name: api_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys ALTER COLUMN id SET DEFAULT nextval('public.api_keys_id_seq'::regclass);


--
-- Name: builders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.builders ALTER COLUMN id SET DEFAULT nextval('public.builders_id_seq'::regclass);


--
-- Name: engagements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements ALTER COLUMN id SET DEFAULT nextval('public.engagements_id_seq'::regclass);


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
-- Name: hubspot_contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hubspot_contacts ALTER COLUMN id SET DEFAULT nextval('public.hubspot_contacts_id_seq'::regclass);


--
-- Name: identities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identities ALTER COLUMN id SET DEFAULT nextval('public.identities_id_seq'::regclass);


--
-- Name: jwt_denylists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jwt_denylists ALTER COLUMN id SET DEFAULT nextval('public.jwt_denylists_id_seq'::regclass);


--
-- Name: luma_event_guests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.luma_event_guests ALTER COLUMN id SET DEFAULT nextval('public.luma_event_guests_id_seq'::regclass);


--
-- Name: luma_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.luma_events ALTER COLUMN id SET DEFAULT nextval('public.luma_events_id_seq'::regclass);


--
-- Name: memos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memos ALTER COLUMN id SET DEFAULT nextval('public.memos_id_seq'::regclass);


--
-- Name: metrics_instagram_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_instagram_stats ALTER COLUMN id SET DEFAULT nextval('public.metrics_instagram_stats_id_seq'::regclass);


--
-- Name: metrics_linkedin_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_linkedin_stats ALTER COLUMN id SET DEFAULT nextval('public.metrics_linkedin_stats_id_seq'::regclass);


--
-- Name: metrics_social_media_account_metric_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_account_metric_snapshots ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_account_metric_snapshots_id_seq'::regclass);


--
-- Name: metrics_social_media_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_accounts ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_accounts_id_seq'::regclass);


--
-- Name: metrics_social_media_ad_account_daily_metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_account_daily_metrics ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_ad_account_daily_metrics_id_seq'::regclass);


--
-- Name: metrics_social_media_ad_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_accounts ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_ad_accounts_id_seq'::regclass);


--
-- Name: metrics_social_media_ad_campaign_daily_metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_campaign_daily_metrics ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_ad_campaign_daily_metrics_id_seq'::regclass);


--
-- Name: metrics_social_media_ad_campaigns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_campaigns ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_ad_campaigns_id_seq'::regclass);


--
-- Name: metrics_social_media_ad_daily_metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_daily_metrics ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_ad_daily_metrics_id_seq'::regclass);


--
-- Name: metrics_social_media_ads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ads ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_ads_id_seq'::regclass);


--
-- Name: metrics_social_media_post_metric_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_post_metric_snapshots ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_post_metric_snapshots_id_seq'::regclass);


--
-- Name: metrics_social_media_posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_posts ALTER COLUMN id SET DEFAULT nextval('public.metrics_social_media_posts_id_seq'::regclass);


--
-- Name: metrics_substack_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_substack_stats ALTER COLUMN id SET DEFAULT nextval('public.metrics_substack_stats_id_seq'::regclass);


--
-- Name: metrics_tiktok_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_tiktok_stats ALTER COLUMN id SET DEFAULT nextval('public.metrics_tiktok_stats_id_seq'::regclass);


--
-- Name: metrics_twitter_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_twitter_stats ALTER COLUMN id SET DEFAULT nextval('public.metrics_twitter_stats_id_seq'::regclass);


--
-- Name: notification_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_batches ALTER COLUMN id SET DEFAULT nextval('public.notification_batches_id_seq'::regclass);


--
-- Name: notification_deliveries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_deliveries ALTER COLUMN id SET DEFAULT nextval('public.notification_deliveries_id_seq'::regclass);


--
-- Name: oauth_access_grants id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_grants_id_seq'::regclass);


--
-- Name: oauth_access_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_tokens_id_seq'::regclass);


--
-- Name: oauth_applications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications ALTER COLUMN id SET DEFAULT nextval('public.oauth_applications_id_seq'::regclass);


--
-- Name: posts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts ALTER COLUMN id SET DEFAULT nextval('public.posts_id_seq'::regclass);


--
-- Name: saved_search_matches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_search_matches ALTER COLUMN id SET DEFAULT nextval('public.saved_search_matches_id_seq'::regclass);


--
-- Name: saved_search_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_search_runs ALTER COLUMN id SET DEFAULT nextval('public.saved_search_runs_id_seq'::regclass);


--
-- Name: saved_searches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_searches ALTER COLUMN id SET DEFAULT nextval('public.saved_searches_id_seq'::regclass);


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
-- Name: trade_barriers_agreement_histories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreement_histories ALTER COLUMN id SET DEFAULT nextval('public.trade_barriers_agreement_histories_id_seq'::regclass);


--
-- Name: trade_barriers_agreement_jurisdictions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreement_jurisdictions ALTER COLUMN id SET DEFAULT nextval('public.trade_barriers_agreement_jurisdictions_id_seq'::regclass);


--
-- Name: trade_barriers_agreements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreements ALTER COLUMN id SET DEFAULT nextval('public.trade_barriers_agreements_id_seq'::regclass);


--
-- Name: trade_barriers_jurisdiction_histories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_jurisdiction_histories ALTER COLUMN id SET DEFAULT nextval('public.trade_barriers_jurisdiction_histories_id_seq'::regclass);


--
-- Name: trade_barriers_themes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_themes ALTER COLUMN id SET DEFAULT nextval('public.trade_barriers_themes_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: addresses id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.addresses ALTER COLUMN id SET DEFAULT nextval('warehouse.addresses_id_seq'::regclass);


--
-- Name: agent_runs id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.agent_runs ALTER COLUMN id SET DEFAULT nextval('warehouse.agent_runs_id_seq'::regclass);


--
-- Name: api_tokens id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.api_tokens ALTER COLUMN id SET DEFAULT nextval('warehouse.api_tokens_id_seq'::regclass);


--
-- Name: canonical_observations id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations ALTER COLUMN id SET DEFAULT nextval('warehouse.canonical_observations_id_seq'::regclass);


--
-- Name: composition_validation_results id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.composition_validation_results ALTER COLUMN id SET DEFAULT nextval('warehouse.composition_validation_results_id_seq'::regclass);


--
-- Name: crosswalk_metric_compatibility id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.crosswalk_metric_compatibility ALTER COLUMN id SET DEFAULT nextval('warehouse.crosswalk_metric_compatibility_id_seq'::regclass);


--
-- Name: derived_observations id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.derived_observations ALTER COLUMN id SET DEFAULT nextval('warehouse.derived_observations_id_seq'::regclass);


--
-- Name: election_candidates id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.election_candidates ALTER COLUMN id SET DEFAULT nextval('warehouse.election_candidates_id_seq'::regclass);


--
-- Name: election_races id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.election_races ALTER COLUMN id SET DEFAULT nextval('warehouse.election_races_id_seq'::regclass);


--
-- Name: elections id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.elections ALTER COLUMN id SET DEFAULT nextval('warehouse.elections_id_seq'::regclass);


--
-- Name: extracted_observations id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations ALTER COLUMN id SET DEFAULT nextval('warehouse.measure_citations_id_seq'::regclass);


--
-- Name: extraction_assertions id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extraction_assertions ALTER COLUMN id SET DEFAULT nextval('warehouse.extraction_assertions_id_seq'::regclass);


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
-- Name: geography_crosswalk_entries id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geography_crosswalk_entries ALTER COLUMN id SET DEFAULT nextval('warehouse.geography_crosswalk_entries_id_seq'::regclass);


--
-- Name: geography_crosswalk_sets id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geography_crosswalk_sets ALTER COLUMN id SET DEFAULT nextval('warehouse.geography_crosswalk_sets_id_seq'::regclass);


--
-- Name: jurisdictions id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.jurisdictions ALTER COLUMN id SET DEFAULT nextval('warehouse.jurisdictions_id_seq'::regclass);


--
-- Name: kpi_documents id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.kpi_documents ALTER COLUMN id SET DEFAULT nextval('warehouse.kpi_documents_id_seq'::regclass);


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
-- Name: measure_lineages id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measure_lineages ALTER COLUMN id SET DEFAULT nextval('warehouse.measure_lineages_id_seq'::regclass);


--
-- Name: measures id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measures ALTER COLUMN id SET DEFAULT nextval('warehouse.measures_id_seq'::regclass);


--
-- Name: media_feed_fetches id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.media_feed_fetches ALTER COLUMN id SET DEFAULT nextval('warehouse.media_feed_fetches_id_seq'::regclass);


--
-- Name: media_feeds id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.media_feeds ALTER COLUMN id SET DEFAULT nextval('warehouse.media_feeds_id_seq'::regclass);


--
-- Name: metric_aliases id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_aliases ALTER COLUMN id SET DEFAULT nextval('warehouse.metric_aliases_id_seq'::regclass);


--
-- Name: metric_component_relationships id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_component_relationships ALTER COLUMN id SET DEFAULT nextval('warehouse.metric_component_relationships_id_seq'::regclass);


--
-- Name: metric_components id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_components ALTER COLUMN id SET DEFAULT nextval('warehouse.metric_components_id_seq'::regclass);


--
-- Name: metric_compositions id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_compositions ALTER COLUMN id SET DEFAULT nextval('warehouse.metric_compositions_id_seq'::regclass);


--
-- Name: metric_versions id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_versions ALTER COLUMN id SET DEFAULT nextval('warehouse.metric_versions_id_seq'::regclass);


--
-- Name: observation_review_flags id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.observation_review_flags ALTER COLUMN id SET DEFAULT nextval('warehouse.observation_review_flags_id_seq'::regclass);


--
-- Name: organization_aliases id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_aliases ALTER COLUMN id SET DEFAULT nextval('warehouse.organization_aliases_id_seq'::regclass);


--
-- Name: organization_lineages id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_lineages ALTER COLUMN id SET DEFAULT nextval('warehouse.organization_lineages_id_seq'::regclass);


--
-- Name: organizations id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organizations ALTER COLUMN id SET DEFAULT nextval('warehouse.organizations_id_seq'::regclass);


--
-- Name: pledges_to_vote id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.pledges_to_vote ALTER COLUMN id SET DEFAULT nextval('warehouse.pledges_to_vote_id_seq'::regclass);


--
-- Name: postal_codes id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.postal_codes ALTER COLUMN id SET DEFAULT nextval('warehouse.postal_codes_id_seq'::regclass);


--
-- Name: raw_ingestions id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.raw_ingestions ALTER COLUMN id SET DEFAULT nextval('warehouse.raw_ingestions_id_seq'::regclass);


--
-- Name: review_decisions id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.review_decisions ALTER COLUMN id SET DEFAULT nextval('warehouse.review_decisions_id_seq'::regclass);


--
-- Name: source_footnotes id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.source_footnotes ALTER COLUMN id SET DEFAULT nextval('warehouse.source_footnotes_id_seq'::regclass);


--
-- Name: sources id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.sources ALTER COLUMN id SET DEFAULT nextval('warehouse.sources_id_seq'::regclass);


--
-- Name: spending_awards id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.spending_awards ALTER COLUMN id SET DEFAULT nextval('warehouse.spending_awards_id_seq'::regclass);


--
-- Name: standard_object_expenditures id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.standard_object_expenditures ALTER COLUMN id SET DEFAULT nextval('warehouse.standard_object_expenditures_id_seq'::regclass);


--
-- Name: units id; Type: DEFAULT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.units ALTER COLUMN id SET DEFAULT nextval('warehouse.units_id_seq'::regclass);


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
-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);


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
-- Name: engagements engagements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements
    ADD CONSTRAINT engagements_pkey PRIMARY KEY (id);


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
-- Name: hubspot_contacts hubspot_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hubspot_contacts
    ADD CONSTRAINT hubspot_contacts_pkey PRIMARY KEY (id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: jwt_denylists jwt_denylists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jwt_denylists
    ADD CONSTRAINT jwt_denylists_pkey PRIMARY KEY (id);


--
-- Name: luma_event_guests luma_event_guests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.luma_event_guests
    ADD CONSTRAINT luma_event_guests_pkey PRIMARY KEY (id);


--
-- Name: luma_events luma_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.luma_events
    ADD CONSTRAINT luma_events_pkey PRIMARY KEY (id);


--
-- Name: memos memos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memos
    ADD CONSTRAINT memos_pkey PRIMARY KEY (id);


--
-- Name: metrics_instagram_stats metrics_instagram_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_instagram_stats
    ADD CONSTRAINT metrics_instagram_stats_pkey PRIMARY KEY (id);


--
-- Name: metrics_linkedin_stats metrics_linkedin_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_linkedin_stats
    ADD CONSTRAINT metrics_linkedin_stats_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_account_metric_snapshots metrics_social_media_account_metric_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_account_metric_snapshots
    ADD CONSTRAINT metrics_social_media_account_metric_snapshots_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_accounts metrics_social_media_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_accounts
    ADD CONSTRAINT metrics_social_media_accounts_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_ad_account_daily_metrics metrics_social_media_ad_account_daily_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_account_daily_metrics
    ADD CONSTRAINT metrics_social_media_ad_account_daily_metrics_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_ad_accounts metrics_social_media_ad_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_accounts
    ADD CONSTRAINT metrics_social_media_ad_accounts_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_ad_campaign_daily_metrics metrics_social_media_ad_campaign_daily_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_campaign_daily_metrics
    ADD CONSTRAINT metrics_social_media_ad_campaign_daily_metrics_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_ad_campaigns metrics_social_media_ad_campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_campaigns
    ADD CONSTRAINT metrics_social_media_ad_campaigns_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_ad_daily_metrics metrics_social_media_ad_daily_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_daily_metrics
    ADD CONSTRAINT metrics_social_media_ad_daily_metrics_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_ads metrics_social_media_ads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ads
    ADD CONSTRAINT metrics_social_media_ads_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_post_metric_snapshots metrics_social_media_post_metric_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_post_metric_snapshots
    ADD CONSTRAINT metrics_social_media_post_metric_snapshots_pkey PRIMARY KEY (id);


--
-- Name: metrics_social_media_posts metrics_social_media_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_posts
    ADD CONSTRAINT metrics_social_media_posts_pkey PRIMARY KEY (id);


--
-- Name: metrics_substack_stats metrics_substack_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_substack_stats
    ADD CONSTRAINT metrics_substack_stats_pkey PRIMARY KEY (id);


--
-- Name: metrics_tiktok_stats metrics_tiktok_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_tiktok_stats
    ADD CONSTRAINT metrics_tiktok_stats_pkey PRIMARY KEY (id);


--
-- Name: metrics_twitter_stats metrics_twitter_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_twitter_stats
    ADD CONSTRAINT metrics_twitter_stats_pkey PRIMARY KEY (id);


--
-- Name: notification_batches notification_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_batches
    ADD CONSTRAINT notification_batches_pkey PRIMARY KEY (id);


--
-- Name: notification_deliveries notification_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_deliveries
    ADD CONSTRAINT notification_deliveries_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_grants oauth_access_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT oauth_access_grants_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_tokens oauth_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT oauth_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: oauth_applications oauth_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications
    ADD CONSTRAINT oauth_applications_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: saved_search_matches saved_search_matches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_search_matches
    ADD CONSTRAINT saved_search_matches_pkey PRIMARY KEY (id);


--
-- Name: saved_search_runs saved_search_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_search_runs
    ADD CONSTRAINT saved_search_runs_pkey PRIMARY KEY (id);


--
-- Name: saved_searches saved_searches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_searches
    ADD CONSTRAINT saved_searches_pkey PRIMARY KEY (id);


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
-- Name: trade_barriers_agreement_histories trade_barriers_agreement_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreement_histories
    ADD CONSTRAINT trade_barriers_agreement_histories_pkey PRIMARY KEY (id);


--
-- Name: trade_barriers_agreement_jurisdictions trade_barriers_agreement_jurisdictions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreement_jurisdictions
    ADD CONSTRAINT trade_barriers_agreement_jurisdictions_pkey PRIMARY KEY (id);


--
-- Name: trade_barriers_agreements trade_barriers_agreements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreements
    ADD CONSTRAINT trade_barriers_agreements_pkey PRIMARY KEY (id);


--
-- Name: trade_barriers_jurisdiction_histories trade_barriers_jurisdiction_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_jurisdiction_histories
    ADD CONSTRAINT trade_barriers_jurisdiction_histories_pkey PRIMARY KEY (id);


--
-- Name: trade_barriers_themes trade_barriers_themes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_themes
    ADD CONSTRAINT trade_barriers_themes_pkey PRIMARY KEY (id);


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
-- Name: agent_runs agent_runs_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.agent_runs
    ADD CONSTRAINT agent_runs_pkey PRIMARY KEY (id);


--
-- Name: api_tokens api_tokens_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.api_tokens
    ADD CONSTRAINT api_tokens_pkey PRIMARY KEY (id);


--
-- Name: canonical_observations canonical_observations_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_pkey PRIMARY KEY (id);


--
-- Name: composition_validation_results composition_validation_results_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.composition_validation_results
    ADD CONSTRAINT composition_validation_results_pkey PRIMARY KEY (id);


--
-- Name: crosswalk_metric_compatibility crosswalk_metric_compatibility_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.crosswalk_metric_compatibility
    ADD CONSTRAINT crosswalk_metric_compatibility_pkey PRIMARY KEY (id);


--
-- Name: derived_observations derived_observations_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.derived_observations
    ADD CONSTRAINT derived_observations_pkey PRIMARY KEY (id);


--
-- Name: election_candidates election_candidates_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.election_candidates
    ADD CONSTRAINT election_candidates_pkey PRIMARY KEY (id);


--
-- Name: election_races election_races_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.election_races
    ADD CONSTRAINT election_races_pkey PRIMARY KEY (id);


--
-- Name: elections elections_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.elections
    ADD CONSTRAINT elections_pkey PRIMARY KEY (id);


--
-- Name: extraction_assertions extraction_assertions_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extraction_assertions
    ADD CONSTRAINT extraction_assertions_pkey PRIMARY KEY (id);


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
-- Name: geography_crosswalk_entries geography_crosswalk_entries_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geography_crosswalk_entries
    ADD CONSTRAINT geography_crosswalk_entries_pkey PRIMARY KEY (id);


--
-- Name: geography_crosswalk_sets geography_crosswalk_sets_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geography_crosswalk_sets
    ADD CONSTRAINT geography_crosswalk_sets_pkey PRIMARY KEY (id);


--
-- Name: jurisdictions jurisdictions_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.jurisdictions
    ADD CONSTRAINT jurisdictions_pkey PRIMARY KEY (id);


--
-- Name: kpi_documents kpi_documents_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.kpi_documents
    ADD CONSTRAINT kpi_documents_pkey PRIMARY KEY (id);


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
-- Name: extracted_observations measure_citations_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT measure_citations_pkey PRIMARY KEY (id);


--
-- Name: measure_footnotes measure_footnotes_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measure_footnotes
    ADD CONSTRAINT measure_footnotes_pkey PRIMARY KEY (measure_id, source_footnote_id);


--
-- Name: measure_lineages measure_lineages_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measure_lineages
    ADD CONSTRAINT measure_lineages_pkey PRIMARY KEY (id);


--
-- Name: measures measures_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measures
    ADD CONSTRAINT measures_pkey PRIMARY KEY (id);


--
-- Name: media_articles media_articles_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.media_articles
    ADD CONSTRAINT media_articles_pkey PRIMARY KEY (id);


--
-- Name: media_feed_fetches media_feed_fetches_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.media_feed_fetches
    ADD CONSTRAINT media_feed_fetches_pkey PRIMARY KEY (id);


--
-- Name: media_feeds media_feeds_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.media_feeds
    ADD CONSTRAINT media_feeds_pkey PRIMARY KEY (id);


--
-- Name: metric_aliases metric_aliases_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_aliases
    ADD CONSTRAINT metric_aliases_pkey PRIMARY KEY (id);


--
-- Name: metric_component_relationships metric_component_relationships_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_component_relationships
    ADD CONSTRAINT metric_component_relationships_pkey PRIMARY KEY (id);


--
-- Name: metric_components metric_components_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_components
    ADD CONSTRAINT metric_components_pkey PRIMARY KEY (id);


--
-- Name: metric_compositions metric_compositions_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_compositions
    ADD CONSTRAINT metric_compositions_pkey PRIMARY KEY (id);


--
-- Name: metric_versions metric_versions_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_versions
    ADD CONSTRAINT metric_versions_pkey PRIMARY KEY (id);


--
-- Name: observation_footnotes observation_footnotes_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.observation_footnotes
    ADD CONSTRAINT observation_footnotes_pkey PRIMARY KEY (extracted_observation_id, source_footnote_id);


--
-- Name: observation_review_flags observation_review_flags_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.observation_review_flags
    ADD CONSTRAINT observation_review_flags_pkey PRIMARY KEY (id);


--
-- Name: organization_aliases organization_aliases_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_aliases
    ADD CONSTRAINT organization_aliases_pkey PRIMARY KEY (id);


--
-- Name: organization_lineages organization_lineages_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_lineages
    ADD CONSTRAINT organization_lineages_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: pledges_to_vote pledges_to_vote_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.pledges_to_vote
    ADD CONSTRAINT pledges_to_vote_pkey PRIMARY KEY (id);


--
-- Name: postal_codes postal_codes_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.postal_codes
    ADD CONSTRAINT postal_codes_pkey PRIMARY KEY (id);


--
-- Name: raw_ingestions raw_ingestions_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.raw_ingestions
    ADD CONSTRAINT raw_ingestions_pkey PRIMARY KEY (id);


--
-- Name: review_decisions review_decisions_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.review_decisions
    ADD CONSTRAINT review_decisions_pkey PRIMARY KEY (id);


--
-- Name: source_footnotes source_footnotes_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.source_footnotes
    ADD CONSTRAINT source_footnotes_pkey PRIMARY KEY (id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);


--
-- Name: spending_awards spending_awards_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.spending_awards
    ADD CONSTRAINT spending_awards_pkey PRIMARY KEY (id);


--
-- Name: standard_object_expenditures standard_object_expenditures_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.standard_object_expenditures
    ADD CONSTRAINT standard_object_expenditures_pkey PRIMARY KEY (id);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (id);


--
-- Name: units units_symbol_key; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.units
    ADD CONSTRAINT units_symbol_key UNIQUE (symbol);


--
-- Name: pledges_to_vote ux_pledges_to_vote_election_subscriber; Type: CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.pledges_to_vote
    ADD CONSTRAINT ux_pledges_to_vote_election_subscriber UNIQUE (election_id, subscriber_id);


--
-- Name: idx_metrics_ad_campaigns_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_metrics_ad_campaigns_account ON public.metrics_social_media_ad_campaigns USING btree (ad_account_id);


--
-- Name: idx_metrics_ads_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_metrics_ads_account ON public.metrics_social_media_ads USING btree (ad_account_id);


--
-- Name: idx_metrics_ads_campaign; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_metrics_ads_campaign ON public.metrics_social_media_ads USING btree (campaign_id);


--
-- Name: idx_notification_batches_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_batches_due ON public.notification_batches USING btree (state, scheduled_for);


--
-- Name: idx_notification_deliveries_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_notification_deliveries_channel ON public.notification_deliveries USING btree (notification_batch_id, channel);


--
-- Name: idx_notification_deliveries_ready; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_deliveries_ready ON public.notification_deliveries USING btree (status, next_attempt_at);


--
-- Name: idx_on_jurisdiction_id_cb07659517; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_jurisdiction_id_cb07659517 ON public.trade_barriers_agreement_jurisdictions USING btree (jurisdiction_id);


--
-- Name: idx_on_memo_id_type_status_created_at_1b33302aff; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_memo_id_type_status_created_at_1b33302aff ON public.engagements USING btree (memo_id, type, status, created_at);


--
-- Name: idx_on_searchable_type_searchable_id_c94ce87143; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_searchable_type_searchable_id_c94ce87143 ON public.saved_search_matches USING btree (searchable_type, searchable_id);


--
-- Name: idx_saved_search_matches_buffer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_saved_search_matches_buffer ON public.saved_search_matches USING btree (saved_search_id, state, matched_at);


--
-- Name: idx_saved_search_matches_dedupe; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_saved_search_matches_dedupe ON public.saved_search_matches USING btree (saved_search_id, match_key);


--
-- Name: idx_saved_search_runs_tick; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_saved_search_runs_tick ON public.saved_search_runs USING btree (saved_search_id, scheduled_for);


--
-- Name: idx_saved_searches_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_saved_searches_due ON public.saved_searches USING btree (enabled, next_run_at);


--
-- Name: idx_social_media_accounts_platform_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_social_media_accounts_platform_key ON public.metrics_social_media_accounts USING btree (platform, account_key);


--
-- Name: idx_social_media_posts_account_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_social_media_posts_account_published ON public.metrics_social_media_posts USING btree (social_media_account_id, published_at);


--
-- Name: idx_social_media_posts_platform_post; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_social_media_posts_platform_post ON public.metrics_social_media_posts USING btree (platform, platform_post_id);


--
-- Name: idx_social_media_posts_social_post; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_social_media_posts_social_post ON public.metrics_social_media_posts USING btree (social_post_id);


--
-- Name: idx_tb_agreement_jurisdictions_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tb_agreement_jurisdictions_unique ON public.trade_barriers_agreement_jurisdictions USING btree (agreement_id, jurisdiction_id);


--
-- Name: idx_tb_jurisdiction_histories_aj_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tb_jurisdiction_histories_aj_id ON public.trade_barriers_jurisdiction_histories USING btree (agreement_jurisdiction_id);


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
-- Name: index_api_keys_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_keys_on_token_digest ON public.api_keys USING btree (token_digest);


--
-- Name: index_api_keys_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_keys_on_user_id ON public.api_keys USING btree (user_id);


--
-- Name: index_api_keys_on_user_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_keys_on_user_id_and_name ON public.api_keys USING btree (user_id, name);


--
-- Name: index_builders_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_builders_on_slug ON public.builders USING btree (slug);


--
-- Name: index_engagements_on_memo_id_and_type_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_engagements_on_memo_id_and_type_and_user_id ON public.engagements USING btree (memo_id, type, user_id);


--
-- Name: index_engagements_on_moderated_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_on_moderated_by_id ON public.engagements USING btree (moderated_by_id);


--
-- Name: index_engagements_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_engagements_on_user_id ON public.engagements USING btree (user_id);


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
-- Name: index_hubspot_contacts_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hubspot_contacts_on_email ON public.hubspot_contacts USING btree (email);


--
-- Name: index_hubspot_contacts_on_full_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hubspot_contacts_on_full_name ON public.hubspot_contacts USING btree (full_name);


--
-- Name: index_hubspot_contacts_on_hs_latest_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hubspot_contacts_on_hs_latest_source ON public.hubspot_contacts USING btree (hs_latest_source);


--
-- Name: index_hubspot_contacts_on_hubspot_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_hubspot_contacts_on_hubspot_contact_id ON public.hubspot_contacts USING btree (hubspot_contact_id);


--
-- Name: index_hubspot_contacts_on_postal_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hubspot_contacts_on_postal_code ON public.hubspot_contacts USING btree (postal_code);


--
-- Name: index_hubspot_contacts_on_synced_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hubspot_contacts_on_synced_at ON public.hubspot_contacts USING btree (synced_at);


--
-- Name: index_identities_on_provider_and_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_identities_on_provider_and_uid ON public.identities USING btree (provider, uid);


--
-- Name: index_identities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identities_on_user_id ON public.identities USING btree (user_id);


--
-- Name: index_jwt_denylists_on_jti; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jwt_denylists_on_jti ON public.jwt_denylists USING btree (jti);


--
-- Name: index_luma_event_guests_on_approval_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_luma_event_guests_on_approval_status ON public.luma_event_guests USING btree (approval_status);


--
-- Name: index_luma_event_guests_on_checked_in; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_luma_event_guests_on_checked_in ON public.luma_event_guests USING btree (checked_in);


--
-- Name: index_luma_event_guests_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_luma_event_guests_on_email ON public.luma_event_guests USING btree (email);


--
-- Name: index_luma_event_guests_on_last_synced_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_luma_event_guests_on_last_synced_at ON public.luma_event_guests USING btree (last_synced_at);


--
-- Name: index_luma_event_guests_on_luma_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_luma_event_guests_on_luma_event_id ON public.luma_event_guests USING btree (luma_event_id);


--
-- Name: index_luma_event_guests_on_luma_event_id_and_luma_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_luma_event_guests_on_luma_event_id_and_luma_user_id ON public.luma_event_guests USING btree (luma_event_id, luma_user_id);


--
-- Name: index_luma_event_guests_on_luma_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_luma_event_guests_on_luma_user_id ON public.luma_event_guests USING btree (luma_user_id);


--
-- Name: index_luma_events_on_last_synced_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_luma_events_on_last_synced_at ON public.luma_events USING btree (last_synced_at);


--
-- Name: index_luma_events_on_luma_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_luma_events_on_luma_event_id ON public.luma_events USING btree (luma_event_id);


--
-- Name: index_luma_events_on_start_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_luma_events_on_start_at ON public.luma_events USING btree (start_at);


--
-- Name: index_luma_events_on_visibility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_luma_events_on_visibility ON public.luma_events USING btree (visibility);


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
-- Name: index_memos_on_slug_and_publication; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memos_on_slug_and_publication ON public.memos USING btree (slug, publication);


--
-- Name: index_metrics_instagram_stats_on_account_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metrics_instagram_stats_on_account_and_date ON public.metrics_instagram_stats USING btree (account, date);


--
-- Name: index_metrics_instagram_stats_on_social_media_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metrics_instagram_stats_on_social_media_account_id ON public.metrics_instagram_stats USING btree (social_media_account_id);


--
-- Name: index_metrics_linkedin_stats_on_account_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metrics_linkedin_stats_on_account_and_date ON public.metrics_linkedin_stats USING btree (account, date);


--
-- Name: index_metrics_linkedin_stats_on_social_media_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metrics_linkedin_stats_on_social_media_account_id ON public.metrics_linkedin_stats USING btree (social_media_account_id);


--
-- Name: index_metrics_substack_stats_on_account_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metrics_substack_stats_on_account_and_date ON public.metrics_substack_stats USING btree (account, date);


--
-- Name: index_metrics_tiktok_stats_on_account_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metrics_tiktok_stats_on_account_and_date ON public.metrics_tiktok_stats USING btree (account, date);


--
-- Name: index_metrics_tiktok_stats_on_social_media_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metrics_tiktok_stats_on_social_media_account_id ON public.metrics_tiktok_stats USING btree (social_media_account_id);


--
-- Name: index_metrics_twitter_stats_on_account_and_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metrics_twitter_stats_on_account_and_date ON public.metrics_twitter_stats USING btree (account, date);


--
-- Name: index_metrics_twitter_stats_on_social_media_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metrics_twitter_stats_on_social_media_account_id ON public.metrics_twitter_stats USING btree (social_media_account_id);


--
-- Name: index_notification_batches_on_saved_search_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notification_batches_on_saved_search_id ON public.notification_batches USING btree (saved_search_id);


--
-- Name: index_notification_deliveries_on_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_notification_deliveries_on_idempotency_key ON public.notification_deliveries USING btree (idempotency_key);


--
-- Name: index_notification_deliveries_on_notification_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notification_deliveries_on_notification_batch_id ON public.notification_deliveries USING btree (notification_batch_id);


--
-- Name: index_oauth_access_grants_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_application_id ON public.oauth_access_grants USING btree (application_id);


--
-- Name: index_oauth_access_grants_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_resource_owner_id ON public.oauth_access_grants USING btree (resource_owner_id);


--
-- Name: index_oauth_access_grants_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_grants_on_token ON public.oauth_access_grants USING btree (token);


--
-- Name: index_oauth_access_tokens_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_application_id ON public.oauth_access_tokens USING btree (application_id);


--
-- Name: index_oauth_access_tokens_on_refresh_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_refresh_token ON public.oauth_access_tokens USING btree (refresh_token);


--
-- Name: index_oauth_access_tokens_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_resource_owner_id ON public.oauth_access_tokens USING btree (resource_owner_id);


--
-- Name: index_oauth_access_tokens_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_token ON public.oauth_access_tokens USING btree (token);


--
-- Name: index_oauth_applications_on_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_applications_on_uid ON public.oauth_applications USING btree (uid);


--
-- Name: index_posts_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_posts_on_slug ON public.posts USING btree (slug);


--
-- Name: index_saved_search_matches_on_notification_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_saved_search_matches_on_notification_batch_id ON public.saved_search_matches USING btree (notification_batch_id);


--
-- Name: index_saved_search_matches_on_saved_search_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_saved_search_matches_on_saved_search_id ON public.saved_search_matches USING btree (saved_search_id);


--
-- Name: index_saved_search_runs_on_saved_search_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_saved_search_runs_on_saved_search_id ON public.saved_search_runs USING btree (saved_search_id);


--
-- Name: index_saved_searches_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_saved_searches_on_user_id ON public.saved_searches USING btree (user_id);


--
-- Name: index_saved_searches_on_user_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_saved_searches_on_user_id_and_name ON public.saved_searches USING btree (user_id, name);


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
-- Name: index_trade_barriers_agreement_histories_on_agreement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trade_barriers_agreement_histories_on_agreement_id ON public.trade_barriers_agreement_histories USING btree (agreement_id);


--
-- Name: index_trade_barriers_agreement_jurisdictions_on_agreement_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trade_barriers_agreement_jurisdictions_on_agreement_id ON public.trade_barriers_agreement_jurisdictions USING btree (agreement_id);


--
-- Name: index_trade_barriers_agreements_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_trade_barriers_agreements_on_slug ON public.trade_barriers_agreements USING btree (slug);


--
-- Name: index_trade_barriers_agreements_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trade_barriers_agreements_on_status ON public.trade_barriers_agreements USING btree (status);


--
-- Name: index_trade_barriers_agreements_on_theme_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trade_barriers_agreements_on_theme_id ON public.trade_barriers_agreements USING btree (theme_id);


--
-- Name: index_trade_barriers_themes_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_trade_barriers_themes_on_name ON public.trade_barriers_themes USING btree (name);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: ux_ad_account_daily_metrics_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_ad_account_daily_metrics_date ON public.metrics_social_media_ad_account_daily_metrics USING btree (ad_account_id, date);


--
-- Name: ux_ad_campaign_daily_metrics_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_ad_campaign_daily_metrics_date ON public.metrics_social_media_ad_campaign_daily_metrics USING btree (campaign_id, date);


--
-- Name: ux_ad_daily_metrics_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_ad_daily_metrics_date ON public.metrics_social_media_ad_daily_metrics USING btree (ad_id, date);


--
-- Name: ux_metrics_ad_accounts_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_metrics_ad_accounts_source_id ON public.metrics_social_media_ad_accounts USING btree (social_media_account_id, platform_ad_account_id);


--
-- Name: ux_metrics_ad_campaigns_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_metrics_ad_campaigns_source_id ON public.metrics_social_media_ad_campaigns USING btree (social_media_account_id, platform, platform_campaign_id);


--
-- Name: ux_metrics_ads_zernio_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_metrics_ads_zernio_id ON public.metrics_social_media_ads USING btree (zernio_ad_id);


--
-- Name: ux_social_media_account_snapshots_observed; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_social_media_account_snapshots_observed ON public.metrics_social_media_account_metric_snapshots USING btree (social_media_account_id, observed_at);


--
-- Name: ux_social_media_accounts_zernio_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_social_media_accounts_zernio_id ON public.metrics_social_media_accounts USING btree (zernio_account_id);


--
-- Name: ux_social_media_post_snapshots_observed; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_social_media_post_snapshots_observed ON public.metrics_social_media_post_metric_snapshots USING btree (social_media_post_id, observed_at);


--
-- Name: ux_social_media_posts_zernio_account; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_social_media_posts_zernio_account ON public.metrics_social_media_posts USING btree (zernio_post_id, social_media_account_id);


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
-- Name: idx_agent_runs_agent_started; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_agent_runs_agent_started ON warehouse.agent_runs USING btree (agent_name, started_at DESC);


--
-- Name: idx_canonical_observations_component; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_canonical_observations_component ON warehouse.canonical_observations USING btree (component_id);


--
-- Name: idx_canonical_observations_composition; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_canonical_observations_composition ON warehouse.canonical_observations USING btree (composition_id);


--
-- Name: idx_canonical_observations_document; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_canonical_observations_document ON warehouse.canonical_observations USING btree (document_id);


--
-- Name: idx_canonical_observations_extracted_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_canonical_observations_extracted_unique ON warehouse.canonical_observations USING btree (extracted_observation_id);


--
-- Name: idx_canonical_observations_jurisdiction; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_canonical_observations_jurisdiction ON warehouse.canonical_observations USING btree (jurisdiction_id);


--
-- Name: idx_canonical_observations_measure_year; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_canonical_observations_measure_year ON warehouse.canonical_observations USING btree (measure_id, measurement_year);


--
-- Name: idx_canonical_observations_metric_version; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_canonical_observations_metric_version ON warehouse.canonical_observations USING btree (metric_version_id);


--
-- Name: idx_canonical_observations_observed_org; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_canonical_observations_observed_org ON warehouse.canonical_observations USING btree (observed_organization_id);


--
-- Name: idx_canonical_observations_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_canonical_observations_unique ON warehouse.canonical_observations USING btree (measure_id, measurement_year, value_type, period_basis, observed_organization_id, geo_boundary_id);


--
-- Name: idx_cmc_set_measure; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_cmc_set_measure ON warehouse.crosswalk_metric_compatibility USING btree (crosswalk_set_id, measure_id);


--
-- Name: idx_crosswalk_entries_from; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_crosswalk_entries_from ON warehouse.geography_crosswalk_entries USING btree (from_geo_id);


--
-- Name: idx_crosswalk_entries_to; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_crosswalk_entries_to ON warehouse.geography_crosswalk_entries USING btree (to_geo_id);


--
-- Name: idx_crosswalk_entries_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_crosswalk_entries_unique ON warehouse.geography_crosswalk_entries USING btree (crosswalk_set_id, from_geo_id, to_geo_id);


--
-- Name: idx_crosswalk_sets_systems_basis; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_crosswalk_sets_systems_basis ON warehouse.geography_crosswalk_sets USING btree (from_code_system, to_code_system, weight_basis);


--
-- Name: idx_cvr_composition; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_cvr_composition ON warehouse.composition_validation_results USING btree (composition_id);


--
-- Name: idx_cvr_status; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_cvr_status ON warehouse.composition_validation_results USING btree (status);


--
-- Name: idx_cvr_year; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_cvr_year ON warehouse.composition_validation_results USING btree (measurement_year);


--
-- Name: idx_derived_observations_crosswalk_set; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_derived_observations_crosswalk_set ON warehouse.derived_observations USING btree (crosswalk_set_id);


--
-- Name: idx_derived_observations_lookup; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_derived_observations_lookup ON warehouse.derived_observations USING btree (measure_id, derived_geo_id, measurement_year);


--
-- Name: idx_derived_observations_measure; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_derived_observations_measure ON warehouse.derived_observations USING btree (measure_id);


--
-- Name: idx_derived_observations_source; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_derived_observations_source ON warehouse.derived_observations USING btree (from_canonical_observation_id);


--
-- Name: idx_election_candidates_status; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_election_candidates_status ON warehouse.election_candidates USING btree (status);


--
-- Name: idx_elections_jurisdiction; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_elections_jurisdiction ON warehouse.elections USING btree (jurisdiction_id);


--
-- Name: idx_extracted_observations_component; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_component ON warehouse.extracted_observations USING btree (component_id);


--
-- Name: idx_extracted_observations_composition; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_composition ON warehouse.extracted_observations USING btree (composition_id);


--
-- Name: idx_extracted_observations_document; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_document ON warehouse.extracted_observations USING btree (document_id);


--
-- Name: idx_extracted_observations_geo_boundary; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_geo_boundary ON warehouse.extracted_observations USING btree (geo_boundary_id);


--
-- Name: idx_extracted_observations_jurisdiction; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_jurisdiction ON warehouse.extracted_observations USING btree (jurisdiction_id);


--
-- Name: idx_extracted_observations_measure_year; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_measure_year ON warehouse.extracted_observations USING btree (measure_id, measurement_year);


--
-- Name: idx_extracted_observations_metric_version; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_metric_version ON warehouse.extracted_observations USING btree (metric_version_id);


--
-- Name: idx_extracted_observations_needs_review; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_needs_review ON warehouse.extracted_observations USING btree (needs_review) WHERE (needs_review = true);


--
-- Name: idx_extracted_observations_observed_org; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_observed_org ON warehouse.extracted_observations USING btree (observed_organization_id);


--
-- Name: idx_extracted_observations_reporting_org; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_reporting_org ON warehouse.extracted_observations USING btree (reporting_organization_id);


--
-- Name: idx_extracted_observations_review_status; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extracted_observations_review_status ON warehouse.extracted_observations USING btree (review_status);


--
-- Name: idx_extracted_observations_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_extracted_observations_unique ON warehouse.extracted_observations USING btree (measure_id, measurement_year, value_type, period_basis, period_start, document_id, composition_id, component_id, observed_organization_id, geo_boundary_id, jurisdiction_id) NULLS NOT DISTINCT;


--
-- Name: idx_extraction_assertions_observation; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extraction_assertions_observation ON warehouse.extraction_assertions USING btree (extracted_observation_id);


--
-- Name: idx_extraction_assertions_type; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_extraction_assertions_type ON warehouse.extraction_assertions USING btree (assertion_type);


--
-- Name: idx_fiscal_authorities_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_fiscal_authorities_unique ON warehouse.fiscal_authorities USING btree (organization_id, fiscal_year, document_type, vote_number);


--
-- Name: idx_fiscal_expenditures_search_sync; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_fiscal_expenditures_search_sync ON warehouse.fiscal_expenditures USING btree (search_synced_at, search_index_sequence);


--
-- Name: idx_fiscal_expenditures_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_fiscal_expenditures_unique ON warehouse.fiscal_expenditures USING btree (organization_id, fiscal_year, vote_number);


--
-- Name: idx_geo_boundaries_code_system; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_geo_boundaries_code_system ON warehouse.geo_boundaries USING btree (code_system);


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
-- Name: idx_kpi_documents_agent_run; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_kpi_documents_agent_run ON warehouse.kpi_documents USING btree (agent_run_id) WHERE (agent_run_id IS NOT NULL);


--
-- Name: idx_kpi_documents_jurisdiction_year; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_kpi_documents_jurisdiction_year ON warehouse.kpi_documents USING btree (jurisdiction_id, fiscal_year);


--
-- Name: idx_kpi_documents_organization; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_kpi_documents_organization ON warehouse.kpi_documents USING btree (organization_id);


--
-- Name: idx_mcr_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_mcr_unique ON warehouse.metric_component_relationships USING btree (from_component_id, to_component_id, relationship_type);


--
-- Name: idx_measure_citations_agent_run; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measure_citations_agent_run ON warehouse.extracted_observations USING btree (agent_run_id) WHERE (agent_run_id IS NOT NULL);


--
-- Name: idx_measure_footnotes_footnote; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measure_footnotes_footnote ON warehouse.measure_footnotes USING btree (source_footnote_id);


--
-- Name: idx_measure_lineages_predecessor; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measure_lineages_predecessor ON warehouse.measure_lineages USING btree (predecessor_id);


--
-- Name: idx_measure_lineages_successor; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measure_lineages_successor ON warehouse.measure_lineages USING btree (successor_id);


--
-- Name: idx_measure_lineages_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_measure_lineages_unique ON warehouse.measure_lineages USING btree (predecessor_id, successor_id, transition_year, transition_kind);


--
-- Name: idx_measures_agent_run; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measures_agent_run ON warehouse.measures USING btree (agent_run_id) WHERE (agent_run_id IS NOT NULL);


--
-- Name: idx_measures_aggregation_type; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measures_aggregation_type ON warehouse.measures USING btree (aggregation_type);


--
-- Name: idx_measures_category; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measures_category ON warehouse.measures USING btree (category);


--
-- Name: idx_measures_cross_agency_slug_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_measures_cross_agency_slug_unique ON warehouse.measures USING btree (slug) WHERE (organization_id IS NULL);


--
-- Name: idx_measures_denominator; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measures_denominator ON warehouse.measures USING btree (denominator_measure_id);


--
-- Name: idx_measures_numerator; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measures_numerator ON warehouse.measures USING btree (numerator_measure_id);


--
-- Name: idx_measures_org_slug_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_measures_org_slug_unique ON warehouse.measures USING btree (organization_id, slug) WHERE (organization_id IS NOT NULL);


--
-- Name: idx_measures_search_sync; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_measures_search_sync ON warehouse.measures USING btree (search_synced_at, search_index_sequence);


--
-- Name: idx_media_articles_canonical_url; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_media_articles_canonical_url ON warehouse.media_articles USING btree (canonical_url_digest) WHERE (canonical_url_digest IS NOT NULL);


--
-- Name: idx_media_articles_media_feed_key; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_media_articles_media_feed_key ON warehouse.media_articles USING btree (media_feed_id, external_key) WHERE ((media_feed_id IS NOT NULL) AND (external_key IS NOT NULL));


--
-- Name: idx_media_articles_sync_overlap; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_media_articles_sync_overlap ON warehouse.media_articles USING btree (search_synced_at, search_index_sequence);


--
-- Name: idx_media_feed_fetches_recent; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_media_feed_fetches_recent ON warehouse.media_feed_fetches USING btree (media_feed_id, created_at);


--
-- Name: idx_media_feeds_due; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_media_feeds_due ON warehouse.media_feeds USING btree (enabled, next_fetch_at);


--
-- Name: idx_metric_aliases_canonical_measure; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_metric_aliases_canonical_measure ON warehouse.metric_aliases USING btree (canonical_measure_id);


--
-- Name: idx_metric_aliases_equivalence_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_metric_aliases_equivalence_unique ON warehouse.metric_aliases USING btree (measure_id, canonical_measure_id) WHERE ((kind)::text = 'measure_equivalence'::text);


--
-- Name: idx_metric_aliases_kind_text; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_metric_aliases_kind_text ON warehouse.metric_aliases USING btree (kind, alias_text);


--
-- Name: idx_metric_aliases_measure; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_metric_aliases_measure ON warehouse.metric_aliases USING btree (measure_id);


--
-- Name: idx_metric_aliases_raw_text_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_metric_aliases_raw_text_unique ON warehouse.metric_aliases USING btree (measure_id, alias_text) WHERE ((kind)::text = 'raw_text'::text);


--
-- Name: idx_metric_components_composition; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_metric_components_composition ON warehouse.metric_components USING btree (composition_id);


--
-- Name: idx_metric_components_measure_type_code; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_metric_components_measure_type_code ON warehouse.metric_components USING btree (measure_id, component_type, component_code) WHERE (component_code IS NOT NULL);


--
-- Name: idx_metric_components_parent; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_metric_components_parent ON warehouse.metric_components USING btree (parent_component_id);


--
-- Name: idx_metric_compositions_measure_type; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_metric_compositions_measure_type ON warehouse.metric_compositions USING btree (measure_id, composition_type);


--
-- Name: idx_metric_versions_document; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_metric_versions_document ON warehouse.metric_versions USING btree (document_id);


--
-- Name: idx_metric_versions_measure; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_metric_versions_measure ON warehouse.metric_versions USING btree (measure_id);


--
-- Name: idx_metric_versions_measure_label; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_metric_versions_measure_label ON warehouse.metric_versions USING btree (measure_id, version_label);


--
-- Name: idx_observation_footnotes_footnote; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_observation_footnotes_footnote ON warehouse.observation_footnotes USING btree (source_footnote_id);


--
-- Name: idx_observation_review_flags_observation; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_observation_review_flags_observation ON warehouse.observation_review_flags USING btree (extracted_observation_id);


--
-- Name: idx_observation_review_flags_open; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_observation_review_flags_open ON warehouse.observation_review_flags USING btree (resolved_at) WHERE (resolved_at IS NULL);


--
-- Name: idx_observation_review_flags_open_severity; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_observation_review_flags_open_severity ON warehouse.observation_review_flags USING btree (severity) WHERE (resolved_at IS NULL);


--
-- Name: idx_observation_review_flags_type; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_observation_review_flags_type ON warehouse.observation_review_flags USING btree (flag_type);


--
-- Name: idx_organization_lineages_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_organization_lineages_unique ON warehouse.organization_lineages USING btree (predecessor_id, successor_id, transition_year, transition_kind);


--
-- Name: idx_organizations_jurisdiction_canonical_name; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_organizations_jurisdiction_canonical_name ON warehouse.organizations USING btree (jurisdiction_id, canonical_name);


--
-- Name: idx_organizations_jurisdiction_slug; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_organizations_jurisdiction_slug ON warehouse.organizations USING btree (jurisdiction_id, slug);


--
-- Name: idx_pledges_to_vote_election_region; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_pledges_to_vote_election_region ON warehouse.pledges_to_vote USING btree (election_id, region);


--
-- Name: idx_pledges_to_vote_pledged_at; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_pledges_to_vote_pledged_at ON warehouse.pledges_to_vote USING btree (pledged_at);


--
-- Name: idx_pledges_to_vote_subscriber; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_pledges_to_vote_subscriber ON warehouse.pledges_to_vote USING btree (subscriber_id);


--
-- Name: idx_postal_codes_lat_lng; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_postal_codes_lat_lng ON warehouse.postal_codes USING btree (latitude, longitude);


--
-- Name: idx_postal_codes_province_code; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_postal_codes_province_code ON warehouse.postal_codes USING btree (province_code);


--
-- Name: idx_review_decisions_created; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_review_decisions_created ON warehouse.review_decisions USING btree (created_at);


--
-- Name: idx_review_decisions_observation; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_review_decisions_observation ON warehouse.review_decisions USING btree (extracted_observation_id);


--
-- Name: idx_review_decisions_reviewer; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_review_decisions_reviewer ON warehouse.review_decisions USING btree (reviewer);


--
-- Name: idx_source_footnotes_document; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_source_footnotes_document ON warehouse.source_footnotes USING btree (document_id);


--
-- Name: idx_source_footnotes_document_marker; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_source_footnotes_document_marker ON warehouse.source_footnotes USING btree (document_id, page, marker);


--
-- Name: idx_spending_awards_canonical_key; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_spending_awards_canonical_key ON warehouse.spending_awards USING btree (source_id, canonical_key);


--
-- Name: idx_spending_awards_search_sync; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_spending_awards_search_sync ON warehouse.spending_awards USING btree (search_synced_at, search_index_sequence);


--
-- Name: idx_spending_awards_searchable; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_spending_awards_searchable ON warehouse.spending_awards USING btree (source_id, is_canonical, state);


--
-- Name: idx_spending_awards_source_key; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_spending_awards_source_key ON warehouse.spending_awards USING btree (source_id, external_key);


--
-- Name: idx_standard_object_expenditures_search_sync; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX idx_standard_object_expenditures_search_sync ON warehouse.standard_object_expenditures USING btree (search_synced_at, search_index_sequence);


--
-- Name: idx_std_obj_expenditures_unique; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX idx_std_obj_expenditures_unique ON warehouse.standard_object_expenditures USING btree (organization_id, fiscal_year, standard_object);


--
-- Name: index_agent_runs_on_status; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_agent_runs_on_status ON warehouse.agent_runs USING btree (status);


--
-- Name: index_api_tokens_on_name; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_api_tokens_on_name ON warehouse.api_tokens USING btree (name);


--
-- Name: index_api_tokens_on_token_hash; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_api_tokens_on_token_hash ON warehouse.api_tokens USING btree (token_hash);


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
-- Name: index_jurisdictions_on_code; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_jurisdictions_on_code ON warehouse.jurisdictions USING btree (code);


--
-- Name: index_jurisdictions_on_slug; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_jurisdictions_on_slug ON warehouse.jurisdictions USING btree (slug);


--
-- Name: index_kpi_documents_on_content_hash; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_kpi_documents_on_content_hash ON warehouse.kpi_documents USING btree (content_hash);


--
-- Name: index_kpi_documents_on_doc_url; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_kpi_documents_on_doc_url ON warehouse.kpi_documents USING btree (doc_url);


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
-- Name: index_measures_on_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_measures_on_organization_id ON warehouse.measures USING btree (organization_id);


--
-- Name: index_measures_on_unit_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_measures_on_unit_id ON warehouse.measures USING btree (unit_id);


--
-- Name: index_media_articles_on_media_feed_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_media_articles_on_media_feed_id ON warehouse.media_articles USING btree (media_feed_id);


--
-- Name: index_media_articles_on_search_index_sequence; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_media_articles_on_search_index_sequence ON warehouse.media_articles USING btree (search_index_sequence);


--
-- Name: index_media_articles_on_state; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_media_articles_on_state ON warehouse.media_articles USING btree (state);


--
-- Name: index_media_feed_fetches_on_media_feed_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_media_feed_fetches_on_media_feed_id ON warehouse.media_feed_fetches USING btree (media_feed_id);


--
-- Name: index_media_feeds_on_name; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_media_feeds_on_name ON warehouse.media_feeds USING btree (name);


--
-- Name: index_organization_aliases_on_alias_name_and_valid_from; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_organization_aliases_on_alias_name_and_valid_from ON warehouse.organization_aliases USING btree (alias_name, valid_from);


--
-- Name: index_organization_aliases_on_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_organization_aliases_on_organization_id ON warehouse.organization_aliases USING btree (organization_id);


--
-- Name: index_organization_lineages_on_predecessor_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_organization_lineages_on_predecessor_id ON warehouse.organization_lineages USING btree (predecessor_id);


--
-- Name: index_organization_lineages_on_successor_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_organization_lineages_on_successor_id ON warehouse.organization_lineages USING btree (successor_id);


--
-- Name: index_organizations_on_jurisdiction_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_organizations_on_jurisdiction_id ON warehouse.organizations USING btree (jurisdiction_id);


--
-- Name: index_organizations_on_org_id_infobase; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_org_id_infobase ON warehouse.organizations USING btree (org_id_infobase) WHERE (org_id_infobase IS NOT NULL);


--
-- Name: index_organizations_on_parent_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_organizations_on_parent_organization_id ON warehouse.organizations USING btree (parent_organization_id);


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
-- Name: index_spending_awards_on_award_type; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_spending_awards_on_award_type ON warehouse.spending_awards USING btree (award_type);


--
-- Name: index_spending_awards_on_fiscal_year; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_spending_awards_on_fiscal_year ON warehouse.spending_awards USING btree (fiscal_year);


--
-- Name: index_spending_awards_on_payer_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_spending_awards_on_payer_organization_id ON warehouse.spending_awards USING btree (payer_organization_id);


--
-- Name: index_spending_awards_on_raw_ingestion_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_spending_awards_on_raw_ingestion_id ON warehouse.spending_awards USING btree (raw_ingestion_id);


--
-- Name: index_spending_awards_on_recipient_name; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_spending_awards_on_recipient_name ON warehouse.spending_awards USING btree (recipient_name);


--
-- Name: index_spending_awards_on_source_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_spending_awards_on_source_id ON warehouse.spending_awards USING btree (source_id);


--
-- Name: index_standard_object_expenditures_on_organization_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_standard_object_expenditures_on_organization_id ON warehouse.standard_object_expenditures USING btree (organization_id);


--
-- Name: index_standard_object_expenditures_on_raw_ingestion_id; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE INDEX index_standard_object_expenditures_on_raw_ingestion_id ON warehouse.standard_object_expenditures USING btree (raw_ingestion_id);


--
-- Name: ux_election_candidates_race_name; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX ux_election_candidates_race_name ON warehouse.election_candidates USING btree (election_race_id, full_name);


--
-- Name: ux_election_races_identity; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX ux_election_races_identity ON warehouse.election_races USING btree (election_id, office_type, COALESCE(office_body, ''::character varying), COALESCE(district_number, 0));


--
-- Name: ux_elections_slug; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX ux_elections_slug ON warehouse.elections USING btree (slug);


--
-- Name: ux_pledges_to_vote_share_token; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX ux_pledges_to_vote_share_token ON warehouse.pledges_to_vote USING btree (share_token);


--
-- Name: ux_postal_codes_postal_code; Type: INDEX; Schema: warehouse; Owner: -
--

CREATE UNIQUE INDEX ux_postal_codes_postal_code ON warehouse.postal_codes USING btree (postal_code);


--
-- Name: human_review_queue _RETURN; Type: RULE; Schema: warehouse; Owner: -
--

CREATE OR REPLACE VIEW warehouse.human_review_queue AS
 SELECT eo.id AS extracted_observation_id,
    eo.measure_id,
    eo.document_id,
    eo.agent_run_id,
    eo.measurement_year,
    eo.value_type,
    eo.period_basis,
    eo.value_numeric,
    eo.value_text,
    eo.value_raw,
    eo.unit_raw,
    eo.metric_name_raw,
    eo.geography_name_raw,
    eo.jurisdiction_name_raw,
    eo.reporting_organization_raw,
    eo.responsible_organization_raw,
    eo.observed_organization_raw,
    eo.evidence_quote,
    eo.source_page,
    eo.source_section,
    eo.source_table,
    eo.extraction_confidence,
    eo.needs_review,
    eo.review_status,
    eo.created_at,
    count(rf.id) FILTER (WHERE (rf.resolved_at IS NULL)) AS open_flag_count,
    max(
        CASE rf.severity
            WHEN 'critical'::text THEN 4
            WHEN 'high'::text THEN 3
            WHEN 'medium'::text THEN 2
            WHEN 'low'::text THEN 1
            ELSE 0
        END) FILTER (WHERE (rf.resolved_at IS NULL)) AS highest_open_severity_rank,
    (array_agg(rf.severity ORDER BY
        CASE rf.severity
            WHEN 'critical'::text THEN 4
            WHEN 'high'::text THEN 3
            WHEN 'medium'::text THEN 2
            WHEN 'low'::text THEN 1
            ELSE 0
        END DESC NULLS LAST, rf.id DESC) FILTER (WHERE (rf.resolved_at IS NULL)))[1] AS highest_open_severity,
    bool_or((rf.resolved_at IS NULL)) AS has_open_flags
   FROM (warehouse.extracted_observations eo
     LEFT JOIN warehouse.observation_review_flags rf ON ((rf.extracted_observation_id = eo.id)))
  WHERE (((eo.review_status)::text = 'pending'::text) AND ((eo.needs_review = true) OR (rf.id IS NOT NULL)))
  GROUP BY eo.id;


--
-- Name: memos fk_rails_03b1037082; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memos
    ADD CONSTRAINT fk_rails_03b1037082 FOREIGN KEY (author_id) REFERENCES public.team_members(id);


--
-- Name: metrics_tiktok_stats fk_rails_0402725fef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_tiktok_stats
    ADD CONSTRAINT fk_rails_0402725fef FOREIGN KEY (social_media_account_id) REFERENCES public.metrics_social_media_accounts(id) ON DELETE SET NULL;


--
-- Name: metrics_twitter_stats fk_rails_0531b4169a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_twitter_stats
    ADD CONSTRAINT fk_rails_0531b4169a FOREIGN KEY (social_media_account_id) REFERENCES public.metrics_social_media_accounts(id) ON DELETE SET NULL;


--
-- Name: metrics_social_media_ad_daily_metrics fk_rails_0667f054d9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_daily_metrics
    ADD CONSTRAINT fk_rails_0667f054d9 FOREIGN KEY (ad_id) REFERENCES public.metrics_social_media_ads(id) ON DELETE CASCADE;


--
-- Name: metrics_social_media_ads fk_rails_09d8c3097d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ads
    ADD CONSTRAINT fk_rails_09d8c3097d FOREIGN KEY (ad_account_id) REFERENCES public.metrics_social_media_ad_accounts(id) ON DELETE SET NULL;


--
-- Name: metrics_social_media_ad_campaigns fk_rails_1a27f2a9a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_campaigns
    ADD CONSTRAINT fk_rails_1a27f2a9a7 FOREIGN KEY (ad_account_id) REFERENCES public.metrics_social_media_ad_accounts(id) ON DELETE SET NULL;


--
-- Name: trade_barriers_agreement_histories fk_rails_2a21dba64b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreement_histories
    ADD CONSTRAINT fk_rails_2a21dba64b FOREIGN KEY (agreement_id) REFERENCES public.trade_barriers_agreements(id);


--
-- Name: api_keys fk_rails_32c28d0dc2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT fk_rails_32c28d0dc2 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: saved_search_runs fk_rails_3ed18251cf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_search_runs
    ADD CONSTRAINT fk_rails_3ed18251cf FOREIGN KEY (saved_search_id) REFERENCES public.saved_searches(id);


--
-- Name: saved_search_matches fk_rails_4bb6ccb533; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_search_matches
    ADD CONSTRAINT fk_rails_4bb6ccb533 FOREIGN KEY (notification_batch_id) REFERENCES public.notification_batches(id);


--
-- Name: saved_search_matches fk_rails_4d2d65163a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_search_matches
    ADD CONSTRAINT fk_rails_4d2d65163a FOREIGN KEY (saved_search_id) REFERENCES public.saved_searches(id);


--
-- Name: identities fk_rails_5373344100; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identities
    ADD CONSTRAINT fk_rails_5373344100 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: engagements fk_rails_53a9175bb0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements
    ADD CONSTRAINT fk_rails_53a9175bb0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: trade_barriers_agreement_jurisdictions fk_rails_59687ac24a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreement_jurisdictions
    ADD CONSTRAINT fk_rails_59687ac24a FOREIGN KEY (agreement_id) REFERENCES public.trade_barriers_agreements(id);


--
-- Name: saved_searches fk_rails_63c5382842; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_searches
    ADD CONSTRAINT fk_rails_63c5382842 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: metrics_social_media_posts fk_rails_65e910fc73; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_posts
    ADD CONSTRAINT fk_rails_65e910fc73 FOREIGN KEY (social_post_id) REFERENCES public.social_posts(id) ON DELETE SET NULL;


--
-- Name: metrics_social_media_ad_campaigns fk_rails_6804420186; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_campaigns
    ADD CONSTRAINT fk_rails_6804420186 FOREIGN KEY (social_media_account_id) REFERENCES public.metrics_social_media_accounts(id) ON DELETE CASCADE;


--
-- Name: notification_batches fk_rails_6e71670cf3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_batches
    ADD CONSTRAINT fk_rails_6e71670cf3 FOREIGN KEY (saved_search_id) REFERENCES public.saved_searches(id);


--
-- Name: oauth_access_tokens fk_rails_732cb83ab7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT fk_rails_732cb83ab7 FOREIGN KEY (application_id) REFERENCES public.oauth_applications(id);


--
-- Name: engagements fk_rails_7e95c5d6f6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements
    ADD CONSTRAINT fk_rails_7e95c5d6f6 FOREIGN KEY (memo_id) REFERENCES public.memos(id);


--
-- Name: trade_barriers_agreements fk_rails_81f3d13d08; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreements
    ADD CONSTRAINT fk_rails_81f3d13d08 FOREIGN KEY (theme_id) REFERENCES public.trade_barriers_themes(id);


--
-- Name: metrics_social_media_ads fk_rails_827edbbf8d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ads
    ADD CONSTRAINT fk_rails_827edbbf8d FOREIGN KEY (social_media_account_id) REFERENCES public.metrics_social_media_accounts(id) ON DELETE CASCADE;


--
-- Name: metrics_linkedin_stats fk_rails_82af9b8cc3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_linkedin_stats
    ADD CONSTRAINT fk_rails_82af9b8cc3 FOREIGN KEY (social_media_account_id) REFERENCES public.metrics_social_media_accounts(id) ON DELETE SET NULL;


--
-- Name: luma_event_guests fk_rails_871979e163; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.luma_event_guests
    ADD CONSTRAINT fk_rails_871979e163 FOREIGN KEY (luma_event_id) REFERENCES public.luma_events(id);


--
-- Name: engagements fk_rails_8e08421d42; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.engagements
    ADD CONSTRAINT fk_rails_8e08421d42 FOREIGN KEY (moderated_by_id) REFERENCES public.users(id);


--
-- Name: metrics_social_media_account_metric_snapshots fk_rails_91139009de; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_account_metric_snapshots
    ADD CONSTRAINT fk_rails_91139009de FOREIGN KEY (social_media_account_id) REFERENCES public.metrics_social_media_accounts(id) ON DELETE CASCADE;


--
-- Name: metrics_instagram_stats fk_rails_91c7fda134; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_instagram_stats
    ADD CONSTRAINT fk_rails_91c7fda134 FOREIGN KEY (social_media_account_id) REFERENCES public.metrics_social_media_accounts(id) ON DELETE SET NULL;


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: metrics_social_media_ads fk_rails_a6240524aa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ads
    ADD CONSTRAINT fk_rails_a6240524aa FOREIGN KEY (campaign_id) REFERENCES public.metrics_social_media_ad_campaigns(id) ON DELETE SET NULL;


--
-- Name: memos fk_rails_a7adfa8924; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memos
    ADD CONSTRAINT fk_rails_a7adfa8924 FOREIGN KEY (co_author_id) REFERENCES public.team_members(id);


--
-- Name: notification_deliveries fk_rails_ac14fefd12; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_deliveries
    ADD CONSTRAINT fk_rails_ac14fefd12 FOREIGN KEY (notification_batch_id) REFERENCES public.notification_batches(id);


--
-- Name: metrics_social_media_ad_account_daily_metrics fk_rails_b36fd8ebe4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_account_daily_metrics
    ADD CONSTRAINT fk_rails_b36fd8ebe4 FOREIGN KEY (ad_account_id) REFERENCES public.metrics_social_media_ad_accounts(id) ON DELETE CASCADE;


--
-- Name: oauth_access_grants fk_rails_b4b53e07b8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT fk_rails_b4b53e07b8 FOREIGN KEY (application_id) REFERENCES public.oauth_applications(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: metrics_social_media_ad_accounts fk_rails_ca905c0cb7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_accounts
    ADD CONSTRAINT fk_rails_ca905c0cb7 FOREIGN KEY (social_media_account_id) REFERENCES public.metrics_social_media_accounts(id) ON DELETE CASCADE;


--
-- Name: metrics_social_media_ad_campaign_daily_metrics fk_rails_d8eb9bb290; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_ad_campaign_daily_metrics
    ADD CONSTRAINT fk_rails_d8eb9bb290 FOREIGN KEY (campaign_id) REFERENCES public.metrics_social_media_ad_campaigns(id) ON DELETE CASCADE;


--
-- Name: metrics_social_media_posts fk_rails_dbf3dce674; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_posts
    ADD CONSTRAINT fk_rails_dbf3dce674 FOREIGN KEY (social_media_account_id) REFERENCES public.metrics_social_media_accounts(id) ON DELETE CASCADE;


--
-- Name: metrics_social_media_post_metric_snapshots fk_rails_e39476749f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics_social_media_post_metric_snapshots
    ADD CONSTRAINT fk_rails_e39476749f FOREIGN KEY (social_media_post_id) REFERENCES public.metrics_social_media_posts(id) ON DELETE CASCADE;


--
-- Name: trade_barriers_agreement_jurisdictions fk_tb_aj_jurisdiction; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_agreement_jurisdictions
    ADD CONSTRAINT fk_tb_aj_jurisdiction FOREIGN KEY (jurisdiction_id) REFERENCES warehouse.jurisdictions(id);


--
-- Name: trade_barriers_jurisdiction_histories fk_tb_jh_aj; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trade_barriers_jurisdiction_histories
    ADD CONSTRAINT fk_tb_jh_aj FOREIGN KEY (agreement_jurisdiction_id) REFERENCES public.trade_barriers_agreement_jurisdictions(id) ON DELETE CASCADE;


--
-- Name: addresses addresses_raw_ingestion_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.addresses
    ADD CONSTRAINT addresses_raw_ingestion_id_fkey FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: canonical_observations canonical_observations_component_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_component_id_fkey FOREIGN KEY (component_id) REFERENCES warehouse.metric_components(id);


--
-- Name: canonical_observations canonical_observations_composition_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_composition_id_fkey FOREIGN KEY (composition_id) REFERENCES warehouse.metric_compositions(id);


--
-- Name: canonical_observations canonical_observations_document_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_document_id_fkey FOREIGN KEY (document_id) REFERENCES warehouse.kpi_documents(id);


--
-- Name: canonical_observations canonical_observations_extracted_observation_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_extracted_observation_id_fkey FOREIGN KEY (extracted_observation_id) REFERENCES warehouse.extracted_observations(id) ON DELETE RESTRICT;


--
-- Name: canonical_observations canonical_observations_geo_boundary_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_geo_boundary_id_fkey FOREIGN KEY (geo_boundary_id) REFERENCES warehouse.geo_boundaries(id);


--
-- Name: canonical_observations canonical_observations_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES warehouse.jurisdictions(id);


--
-- Name: canonical_observations canonical_observations_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: canonical_observations canonical_observations_metric_version_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_metric_version_id_fkey FOREIGN KEY (metric_version_id) REFERENCES warehouse.metric_versions(id);


--
-- Name: canonical_observations canonical_observations_observed_organization_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_observed_organization_id_fkey FOREIGN KEY (observed_organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: canonical_observations canonical_observations_reporting_organization_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_reporting_organization_id_fkey FOREIGN KEY (reporting_organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: canonical_observations canonical_observations_responsible_organization_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_responsible_organization_id_fkey FOREIGN KEY (responsible_organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: canonical_observations canonical_observations_unit_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.canonical_observations
    ADD CONSTRAINT canonical_observations_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES warehouse.units(id);


--
-- Name: composition_validation_results composition_validation_results_composition_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.composition_validation_results
    ADD CONSTRAINT composition_validation_results_composition_id_fkey FOREIGN KEY (composition_id) REFERENCES warehouse.metric_compositions(id) ON DELETE CASCADE;


--
-- Name: composition_validation_results composition_validation_results_geo_boundary_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.composition_validation_results
    ADD CONSTRAINT composition_validation_results_geo_boundary_id_fkey FOREIGN KEY (geo_boundary_id) REFERENCES warehouse.geo_boundaries(id);


--
-- Name: composition_validation_results composition_validation_results_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.composition_validation_results
    ADD CONSTRAINT composition_validation_results_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: composition_validation_results composition_validation_results_observed_organization_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.composition_validation_results
    ADD CONSTRAINT composition_validation_results_observed_organization_id_fkey FOREIGN KEY (observed_organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: crosswalk_metric_compatibility crosswalk_metric_compatibility_crosswalk_set_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.crosswalk_metric_compatibility
    ADD CONSTRAINT crosswalk_metric_compatibility_crosswalk_set_id_fkey FOREIGN KEY (crosswalk_set_id) REFERENCES warehouse.geography_crosswalk_sets(id) ON DELETE CASCADE;


--
-- Name: crosswalk_metric_compatibility crosswalk_metric_compatibility_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.crosswalk_metric_compatibility
    ADD CONSTRAINT crosswalk_metric_compatibility_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: derived_observations derived_observations_crosswalk_set_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.derived_observations
    ADD CONSTRAINT derived_observations_crosswalk_set_id_fkey FOREIGN KEY (crosswalk_set_id) REFERENCES warehouse.geography_crosswalk_sets(id) ON DELETE SET NULL;


--
-- Name: derived_observations derived_observations_derived_geo_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.derived_observations
    ADD CONSTRAINT derived_observations_derived_geo_id_fkey FOREIGN KEY (derived_geo_id) REFERENCES warehouse.geo_boundaries(id);


--
-- Name: derived_observations derived_observations_from_canonical_observation_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.derived_observations
    ADD CONSTRAINT derived_observations_from_canonical_observation_id_fkey FOREIGN KEY (from_canonical_observation_id) REFERENCES warehouse.canonical_observations(id) ON DELETE SET NULL;


--
-- Name: derived_observations derived_observations_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.derived_observations
    ADD CONSTRAINT derived_observations_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: derived_observations derived_observations_original_geo_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.derived_observations
    ADD CONSTRAINT derived_observations_original_geo_id_fkey FOREIGN KEY (original_geo_id) REFERENCES warehouse.geo_boundaries(id);


--
-- Name: derived_observations derived_observations_unit_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.derived_observations
    ADD CONSTRAINT derived_observations_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES warehouse.units(id);


--
-- Name: election_candidates election_candidates_election_race_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.election_candidates
    ADD CONSTRAINT election_candidates_election_race_id_fkey FOREIGN KEY (election_race_id) REFERENCES warehouse.election_races(id) ON DELETE CASCADE;


--
-- Name: election_races election_races_election_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.election_races
    ADD CONSTRAINT election_races_election_id_fkey FOREIGN KEY (election_id) REFERENCES warehouse.elections(id) ON DELETE CASCADE;


--
-- Name: elections elections_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.elections
    ADD CONSTRAINT elections_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES warehouse.jurisdictions(id);


--
-- Name: extracted_observations extracted_observations_component_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT extracted_observations_component_id_fkey FOREIGN KEY (component_id) REFERENCES warehouse.metric_components(id);


--
-- Name: extracted_observations extracted_observations_composition_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT extracted_observations_composition_id_fkey FOREIGN KEY (composition_id) REFERENCES warehouse.metric_compositions(id);


--
-- Name: extracted_observations extracted_observations_geo_boundary_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT extracted_observations_geo_boundary_id_fkey FOREIGN KEY (geo_boundary_id) REFERENCES warehouse.geo_boundaries(id);


--
-- Name: extracted_observations extracted_observations_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT extracted_observations_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES warehouse.jurisdictions(id);


--
-- Name: extracted_observations extracted_observations_metric_version_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT extracted_observations_metric_version_id_fkey FOREIGN KEY (metric_version_id) REFERENCES warehouse.metric_versions(id);


--
-- Name: extracted_observations extracted_observations_observed_organization_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT extracted_observations_observed_organization_id_fkey FOREIGN KEY (observed_organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: extracted_observations extracted_observations_reporting_organization_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT extracted_observations_reporting_organization_id_fkey FOREIGN KEY (reporting_organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: extracted_observations extracted_observations_responsible_organization_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT extracted_observations_responsible_organization_id_fkey FOREIGN KEY (responsible_organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: extraction_assertions extraction_assertions_extracted_observation_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extraction_assertions
    ADD CONSTRAINT extraction_assertions_extracted_observation_id_fkey FOREIGN KEY (extracted_observation_id) REFERENCES warehouse.extracted_observations(id) ON DELETE CASCADE;


--
-- Name: organization_lineages fk_organization_lineages_acknowledged_doc; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_lineages
    ADD CONSTRAINT fk_organization_lineages_acknowledged_doc FOREIGN KEY (acknowledged_in_document_id) REFERENCES warehouse.kpi_documents(id);


--
-- Name: organizations fk_organizations_jurisdiction; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organizations
    ADD CONSTRAINT fk_organizations_jurisdiction FOREIGN KEY (jurisdiction_id) REFERENCES warehouse.jurisdictions(id);


--
-- Name: organizations fk_organizations_parent; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organizations
    ADD CONSTRAINT fk_organizations_parent FOREIGN KEY (parent_organization_id) REFERENCES warehouse.organizations(id);


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
-- Name: spending_awards fk_rails_245c5b1a24; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.spending_awards
    ADD CONSTRAINT fk_rails_245c5b1a24 FOREIGN KEY (payer_organization_id) REFERENCES warehouse.organizations(id);


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
-- Name: spending_awards fk_rails_4b18c39624; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.spending_awards
    ADD CONSTRAINT fk_rails_4b18c39624 FOREIGN KEY (source_id) REFERENCES warehouse.sources(id);


--
-- Name: lineage_entries fk_rails_508c5de983; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.lineage_entries
    ADD CONSTRAINT fk_rails_508c5de983 FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: media_articles fk_rails_5ebd13ee23; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.media_articles
    ADD CONSTRAINT fk_rails_5ebd13ee23 FOREIGN KEY (media_feed_id) REFERENCES warehouse.media_feeds(id);


--
-- Name: media_feed_fetches fk_rails_75522ea188; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.media_feed_fetches
    ADD CONSTRAINT fk_rails_75522ea188 FOREIGN KEY (media_feed_id) REFERENCES warehouse.media_feeds(id);


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
-- Name: spending_awards fk_rails_90e55d982c; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.spending_awards
    ADD CONSTRAINT fk_rails_90e55d982c FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


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
-- Name: geography_crosswalk_entries geography_crosswalk_entries_crosswalk_set_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geography_crosswalk_entries
    ADD CONSTRAINT geography_crosswalk_entries_crosswalk_set_id_fkey FOREIGN KEY (crosswalk_set_id) REFERENCES warehouse.geography_crosswalk_sets(id) ON DELETE CASCADE;


--
-- Name: geography_crosswalk_entries geography_crosswalk_entries_from_geo_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geography_crosswalk_entries
    ADD CONSTRAINT geography_crosswalk_entries_from_geo_id_fkey FOREIGN KEY (from_geo_id) REFERENCES warehouse.geo_boundaries(id) ON DELETE CASCADE;


--
-- Name: geography_crosswalk_entries geography_crosswalk_entries_to_geo_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geography_crosswalk_entries
    ADD CONSTRAINT geography_crosswalk_entries_to_geo_id_fkey FOREIGN KEY (to_geo_id) REFERENCES warehouse.geo_boundaries(id) ON DELETE CASCADE;


--
-- Name: geography_crosswalk_sets geography_crosswalk_sets_source_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.geography_crosswalk_sets
    ADD CONSTRAINT geography_crosswalk_sets_source_id_fkey FOREIGN KEY (source_id) REFERENCES warehouse.sources(id);


--
-- Name: kpi_documents kpi_documents_agent_run_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.kpi_documents
    ADD CONSTRAINT kpi_documents_agent_run_id_fkey FOREIGN KEY (agent_run_id) REFERENCES warehouse.agent_runs(id);


--
-- Name: kpi_documents kpi_documents_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.kpi_documents
    ADD CONSTRAINT kpi_documents_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES warehouse.jurisdictions(id);


--
-- Name: kpi_documents kpi_documents_organization_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.kpi_documents
    ADD CONSTRAINT kpi_documents_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: kpi_documents kpi_documents_raw_ingestion_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.kpi_documents
    ADD CONSTRAINT kpi_documents_raw_ingestion_id_fkey FOREIGN KEY (raw_ingestion_id) REFERENCES warehouse.raw_ingestions(id);


--
-- Name: extracted_observations measure_citations_agent_run_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT measure_citations_agent_run_id_fkey FOREIGN KEY (agent_run_id) REFERENCES warehouse.agent_runs(id);


--
-- Name: extracted_observations measure_citations_document_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT measure_citations_document_id_fkey FOREIGN KEY (document_id) REFERENCES warehouse.kpi_documents(id);


--
-- Name: extracted_observations measure_citations_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.extracted_observations
    ADD CONSTRAINT measure_citations_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: measure_footnotes measure_footnotes_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measure_footnotes
    ADD CONSTRAINT measure_footnotes_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: measure_footnotes measure_footnotes_source_footnote_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measure_footnotes
    ADD CONSTRAINT measure_footnotes_source_footnote_id_fkey FOREIGN KEY (source_footnote_id) REFERENCES warehouse.source_footnotes(id) ON DELETE CASCADE;


--
-- Name: measure_lineages measure_lineages_acknowledged_in_document_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measure_lineages
    ADD CONSTRAINT measure_lineages_acknowledged_in_document_id_fkey FOREIGN KEY (acknowledged_in_document_id) REFERENCES warehouse.kpi_documents(id);


--
-- Name: measure_lineages measure_lineages_predecessor_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measure_lineages
    ADD CONSTRAINT measure_lineages_predecessor_id_fkey FOREIGN KEY (predecessor_id) REFERENCES warehouse.measures(id);


--
-- Name: measure_lineages measure_lineages_successor_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measure_lineages
    ADD CONSTRAINT measure_lineages_successor_id_fkey FOREIGN KEY (successor_id) REFERENCES warehouse.measures(id);


--
-- Name: measures measures_agent_run_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measures
    ADD CONSTRAINT measures_agent_run_id_fkey FOREIGN KEY (agent_run_id) REFERENCES warehouse.agent_runs(id);


--
-- Name: measures measures_denominator_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measures
    ADD CONSTRAINT measures_denominator_measure_id_fkey FOREIGN KEY (denominator_measure_id) REFERENCES warehouse.measures(id);


--
-- Name: measures measures_numerator_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measures
    ADD CONSTRAINT measures_numerator_measure_id_fkey FOREIGN KEY (numerator_measure_id) REFERENCES warehouse.measures(id);


--
-- Name: measures measures_organization_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measures
    ADD CONSTRAINT measures_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES warehouse.organizations(id);


--
-- Name: measures measures_unit_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.measures
    ADD CONSTRAINT measures_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES warehouse.units(id);


--
-- Name: metric_aliases metric_aliases_canonical_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_aliases
    ADD CONSTRAINT metric_aliases_canonical_measure_id_fkey FOREIGN KEY (canonical_measure_id) REFERENCES warehouse.measures(id);


--
-- Name: metric_aliases metric_aliases_document_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_aliases
    ADD CONSTRAINT metric_aliases_document_id_fkey FOREIGN KEY (document_id) REFERENCES warehouse.kpi_documents(id);


--
-- Name: metric_aliases metric_aliases_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_aliases
    ADD CONSTRAINT metric_aliases_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: metric_aliases metric_aliases_source_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_aliases
    ADD CONSTRAINT metric_aliases_source_id_fkey FOREIGN KEY (source_id) REFERENCES warehouse.sources(id);


--
-- Name: metric_component_relationships metric_component_relationships_from_component_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_component_relationships
    ADD CONSTRAINT metric_component_relationships_from_component_id_fkey FOREIGN KEY (from_component_id) REFERENCES warehouse.metric_components(id) ON DELETE CASCADE;


--
-- Name: metric_component_relationships metric_component_relationships_source_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_component_relationships
    ADD CONSTRAINT metric_component_relationships_source_id_fkey FOREIGN KEY (source_id) REFERENCES warehouse.sources(id);


--
-- Name: metric_component_relationships metric_component_relationships_to_component_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_component_relationships
    ADD CONSTRAINT metric_component_relationships_to_component_id_fkey FOREIGN KEY (to_component_id) REFERENCES warehouse.metric_components(id) ON DELETE CASCADE;


--
-- Name: metric_components metric_components_composition_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_components
    ADD CONSTRAINT metric_components_composition_id_fkey FOREIGN KEY (composition_id) REFERENCES warehouse.metric_compositions(id) ON DELETE CASCADE;


--
-- Name: metric_components metric_components_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_components
    ADD CONSTRAINT metric_components_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: metric_components metric_components_parent_component_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_components
    ADD CONSTRAINT metric_components_parent_component_id_fkey FOREIGN KEY (parent_component_id) REFERENCES warehouse.metric_components(id);


--
-- Name: metric_compositions metric_compositions_expected_total_unit_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_compositions
    ADD CONSTRAINT metric_compositions_expected_total_unit_id_fkey FOREIGN KEY (expected_total_unit_id) REFERENCES warehouse.units(id);


--
-- Name: metric_compositions metric_compositions_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_compositions
    ADD CONSTRAINT metric_compositions_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: metric_versions metric_versions_document_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_versions
    ADD CONSTRAINT metric_versions_document_id_fkey FOREIGN KEY (document_id) REFERENCES warehouse.kpi_documents(id);


--
-- Name: metric_versions metric_versions_measure_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_versions
    ADD CONSTRAINT metric_versions_measure_id_fkey FOREIGN KEY (measure_id) REFERENCES warehouse.measures(id) ON DELETE CASCADE;


--
-- Name: metric_versions metric_versions_source_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.metric_versions
    ADD CONSTRAINT metric_versions_source_id_fkey FOREIGN KEY (source_id) REFERENCES warehouse.sources(id);


--
-- Name: observation_footnotes observation_footnotes_extracted_observation_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.observation_footnotes
    ADD CONSTRAINT observation_footnotes_extracted_observation_id_fkey FOREIGN KEY (extracted_observation_id) REFERENCES warehouse.extracted_observations(id) ON DELETE CASCADE;


--
-- Name: observation_footnotes observation_footnotes_source_footnote_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.observation_footnotes
    ADD CONSTRAINT observation_footnotes_source_footnote_id_fkey FOREIGN KEY (source_footnote_id) REFERENCES warehouse.source_footnotes(id) ON DELETE CASCADE;


--
-- Name: observation_review_flags observation_review_flags_extracted_observation_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.observation_review_flags
    ADD CONSTRAINT observation_review_flags_extracted_observation_id_fkey FOREIGN KEY (extracted_observation_id) REFERENCES warehouse.extracted_observations(id) ON DELETE CASCADE;


--
-- Name: organization_lineages organization_lineages_predecessor_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_lineages
    ADD CONSTRAINT organization_lineages_predecessor_id_fkey FOREIGN KEY (predecessor_id) REFERENCES warehouse.organizations(id);


--
-- Name: organization_lineages organization_lineages_successor_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.organization_lineages
    ADD CONSTRAINT organization_lineages_successor_id_fkey FOREIGN KEY (successor_id) REFERENCES warehouse.organizations(id);


--
-- Name: pledges_to_vote pledges_to_vote_election_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.pledges_to_vote
    ADD CONSTRAINT pledges_to_vote_election_id_fkey FOREIGN KEY (election_id) REFERENCES warehouse.elections(id) ON DELETE CASCADE;


--
-- Name: pledges_to_vote pledges_to_vote_subscriber_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.pledges_to_vote
    ADD CONSTRAINT pledges_to_vote_subscriber_id_fkey FOREIGN KEY (subscriber_id) REFERENCES public.subscribers(id) ON DELETE CASCADE;


--
-- Name: review_decisions review_decisions_extracted_observation_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.review_decisions
    ADD CONSTRAINT review_decisions_extracted_observation_id_fkey FOREIGN KEY (extracted_observation_id) REFERENCES warehouse.extracted_observations(id) ON DELETE CASCADE;


--
-- Name: source_footnotes source_footnotes_agent_run_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.source_footnotes
    ADD CONSTRAINT source_footnotes_agent_run_id_fkey FOREIGN KEY (agent_run_id) REFERENCES warehouse.agent_runs(id) ON DELETE SET NULL;


--
-- Name: source_footnotes source_footnotes_document_id_fkey; Type: FK CONSTRAINT; Schema: warehouse; Owner: -
--

ALTER TABLE ONLY warehouse.source_footnotes
    ADD CONSTRAINT source_footnotes_document_id_fkey FOREIGN KEY (document_id) REFERENCES warehouse.kpi_documents(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO public,warehouse;

INSERT INTO "schema_migrations" (version) VALUES
('20260810181000'),
('20260810180000'),
('20260807000001'),
('20260805050000'),
('20260805040000'),
('20260805020000'),
('20260805011200'),
('20260805011100'),
('20260805011000'),
('20260805010900'),
('20260805010800'),
('20260805010700'),
('20260805010600'),
('20260805010500'),
('20260805010400'),
('20260805010200'),
('20260805010100'),
('20260805010000'),
('20260729000002'),
('20260729000001'),
('20260728000001'),
('20260724000001'),
('20260723000002'),
('20260723000001'),
('20260722160000'),
('20260722153000'),
('20260722000003'),
('20260722000002'),
('20260722000001'),
('20260721000003'),
('20260721000002'),
('20260721000001'),
('20260714000001'),
('20260710000001'),
('20260709000001'),
('20260708000002'),
('20260708000001'),
('20260617145412'),
('20260617145403'),
('20260603000001'),
('20260602000001'),
('20260528000013'),
('20260528000012'),
('20260528000011'),
('20260528000010'),
('20260528000009'),
('20260528000008'),
('20260528000007'),
('20260528000006'),
('20260528000005'),
('20260528000004'),
('20260528000003'),
('20260528000002'),
('20260528000001'),
('20260527000003'),
('20260527000002'),
('20260527000001'),
('20260526000001'),
('20260525000007'),
('20260525000006'),
('20260525000005'),
('20260525000004'),
('20260525000003'),
('20260525000002'),
('20260525000001'),
('20260513180113'),
('20260510000003'),
('20260510000001'),
('20260504204633'),
('20260428000002'),
('20260428000001'),
('20260424000002'),
('20260424000001'),
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
