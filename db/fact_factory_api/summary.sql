-- VENDORED from BuildCanada/fact-factory, src/fact_factory/serve/read_model.py SUMMARY_SQL (with MEASURES filled in)
-- at 7a570c2 (PR #27). The read model builds api.spending_summary with it for release $1 (:n there).
-- york_factory never runs it against the real read model: the tests build their fixture summary with it
-- (test/support/fact_factory_api_database.rb), and so does script/public_api/explain.rb.
INSERT INTO api.spending_summary (release_id, entity_id, role, asset_key, source_key, fiscal_year, currency,
  measure, record_count, agreement_count, amount, amount_missing_count, aggregated_excluded, revisions_excluded)
WITH linked AS (
  SELECT DISTINCT p.entity_id,
    CASE p.field WHEN 'payer' THEN 'payer' WHEN 'research_org' THEN 'research_org' ELSE 'recipient' END AS role,
    p.asset_key, p.spending_row_id
  FROM api.spending_parties p
  WHERE p.entity_id IS NOT NULL AND p.acquisition = 'live' AND api.in_release(p.release_from, p.release_to, $1)
), live AS (
  SELECT DISTINCT ON (r.asset_key, r.id) r.asset_key, r.source_key, r.id, r.canonical_id, r.revision_rank,
    r.fiscal_year, r.currency, r.amount, coalesce(r.is_aggregated, false) AS is_aggregated
  FROM api.spending_records r
  WHERE r.acquisition = 'live' AND api.in_release(r.release_from, r.release_to, $1)
    AND (r.asset_key, r.canonical_id) IN (
      SELECT r2.asset_key, r2.canonical_id FROM api.spending_records r2 JOIN linked l
        ON l.asset_key = r2.asset_key AND l.spending_row_id = r2.id
      WHERE r2.acquisition = 'live' AND api.in_release(r2.release_from, r2.release_to, $1))
  ORDER BY r.asset_key, r.id, r.resource_id, r.source_occurrence
), ranked AS (
  SELECT live.*, (revision_rank IS NULL OR row_number() OVER (
      PARTITION BY asset_key, canonical_id ORDER BY revision_rank DESC NULLS LAST, id DESC) = 1) AS latest
  FROM live
), measures (source_key, measure) AS (VALUES ('proactive_contracts', 'contract_value'), ('aggregated_contracts', 'aggregated_contract_value'), ('proactive_grants', 'agreement_value'), ('transfer_payments', 'payments_or_expenditure'), ('nserc_awards', 'award_amount'), ('sshrc_awards', 'award_amount'), ('cihr_awards', 'award_amount'), ('global_affairs_projects', 'commitment'))
SELECT $1, l.entity_id, l.role, r.asset_key, r.source_key, r.fiscal_year, r.currency,
  coalesce(m.measure, 'amount'),
  count(*) FILTER (WHERE r.latest AND NOT r.is_aggregated),
  count(DISTINCT r.canonical_id) FILTER (WHERE r.latest AND NOT r.is_aggregated),
  sum(r.amount) FILTER (WHERE r.latest AND NOT r.is_aggregated),
  count(*) FILTER (WHERE r.latest AND NOT r.is_aggregated AND r.amount IS NULL),
  count(*) FILTER (WHERE r.is_aggregated),
  count(*) FILTER (WHERE NOT r.latest AND NOT r.is_aggregated)
FROM linked l
JOIN ranked r ON r.asset_key = l.asset_key AND r.id = l.spending_row_id
LEFT JOIN measures m ON m.source_key = r.source_key
GROUP BY l.entity_id, l.role, r.asset_key, r.source_key, r.fiscal_year, r.currency, m.measure
