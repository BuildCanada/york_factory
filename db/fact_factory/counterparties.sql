-- VENDORED from BuildCanada/fact-factory src/fact_factory/derived.py at f0d4918:
-- COUNTERPARTY_SQL, formatted with {mine} empty (every entity) and MEASURES.
-- It reads the temporary table derived_pubs (state, asset_key, publication_id) and the bind :n.
-- The tests build their fixture derived tables with it (test/support/fact_factory_database.rb).

INSERT INTO fact_factory.spending_counterparties (entity_id, role, counterparty_id, asset_key, source_key,
  fiscal_year, currency, measure, record_count, agreement_count, amount, amount_missing_count,
  aggregated_excluded, revisions_excluded, revision_id)
WITH parties AS (
  SELECT DISTINCT o.entity_id, CASE o.field WHEN 'payer' THEN 'payer' ELSE 'recipient' END AS role, o.source_key AS asset_key, o.spending_row_id
  FROM fact_factory.mention_occurrences o
  WHERE o.entity_id IS NOT NULL AND position('@' in o.source_key) = 0 AND o.field IN ('payer', 'recipient', 'recipients', 'principal_investigator', 'vendor_name') AND o.revision_id <= :n AND (o.retired_revision_id IS NULL OR o.retired_revision_id > :n)
), mine AS (
  SELECT * FROM parties o WHERE true 
), live AS (
  SELECT DISTINCT ON (lp.asset_key, r.id) lp.asset_key, r.source_key, r.id, r.canonical_id,
    CAST(r.revision_rank_json AS jsonb) AS revision_rank, r.fiscal_year, r.currency, r.amount,
    coalesce(r.is_aggregated, false) AS is_aggregated
  FROM fact_factory.spending_records r JOIN derived_pubs lp ON lp.publication_id = r.publication_id AND lp.state = 'n'
  WHERE (lp.asset_key, r.canonical_id) IN (
      SELECT lp2.asset_key, r2.canonical_id FROM fact_factory.spending_records r2
      JOIN derived_pubs lp2 ON lp2.publication_id = r2.publication_id AND lp2.state = 'n'
      JOIN mine l ON l.asset_key = lp2.asset_key AND l.spending_row_id = r2.id)
  ORDER BY lp.asset_key, r.id, r.resource_id, r.source_occurrence
), ranked AS (
  SELECT live.*, (revision_rank IS NULL OR row_number() OVER (
      PARTITION BY asset_key, canonical_id ORDER BY revision_rank DESC NULLS LAST, id DESC) = 1) AS latest
  FROM live
), measures (source_key, measure) AS (VALUES ('proactive_contracts', 'contract_value'), ('aggregated_contracts', 'aggregated_contract_value'), ('proactive_grants', 'agreement_value'), ('transfer_payments', 'payments_or_expenditure'), ('nserc_awards', 'award_amount'), ('sshrc_awards', 'award_amount'), ('cihr_awards', 'award_amount'), ('global_affairs_projects', 'commitment'))
SELECT l.entity_id, l.role, o.entity_id, r.asset_key, r.source_key, r.fiscal_year, r.currency,
  coalesce(m.measure, 'amount'),
  count(*) FILTER (WHERE r.latest AND NOT r.is_aggregated),
  count(DISTINCT r.canonical_id) FILTER (WHERE r.latest AND NOT r.is_aggregated),
  sum(r.amount) FILTER (WHERE r.latest AND NOT r.is_aggregated),
  count(*) FILTER (WHERE r.latest AND NOT r.is_aggregated AND r.amount IS NULL),
  count(*) FILTER (WHERE r.is_aggregated),
  count(*) FILTER (WHERE NOT r.latest AND NOT r.is_aggregated),
  :n
FROM mine l
JOIN ranked r ON r.asset_key = l.asset_key AND r.id = l.spending_row_id
LEFT JOIN parties o ON o.asset_key = r.asset_key AND o.spending_row_id = r.id AND o.role <> l.role
LEFT JOIN measures m ON m.source_key = r.source_key
GROUP BY l.entity_id, l.role, o.entity_id, r.asset_key, r.source_key, r.fiscal_year, r.currency, m.measure
