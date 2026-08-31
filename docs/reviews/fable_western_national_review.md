# Fable review: Alberta/BC output and national expansion

Review date: 2026-08-21
Review session: `ontology-fable-west-national`
Reviewer: Claude Fable, read-only repository and Parquet review

## Release-blocking findings

1. Alberta's Kananaskis slug fell through a numbered-improvement-district parser and became the degenerate `ca/ab/improvement-district`. Fix before the semantic ID propagates.
2. `ca/fn/shishalh-nation-government-district` conflates the shíshálh Nation Government District, a B.C. local-government entity, with the separate shíshálh Nation. Put the district in `ca/bc/`, reserve `ca/fn/` for the Nation/band adapter, and relate the two only from legal evidence.
3. B.C. SOFI disclosures, audited financial statements, and annual reports were collapsed into two types. Make SOFI reachable as `statement-of-financial-information`; do not infer an annual report's reporting period blindly from its publication-title year.
4. The relationship graph was empty. Add real sourced predecessor/successor, membership, control, and hierarchy assertions; Diamond Valley and its two predecessor towns are the first concrete succession case.
5. Fable questioned the future Okanagan Falls activation date. Independent adjudication against current B.C. primary sources confirms the implementation is correct: letters patent were issued June 24, 2026 and incorporation takes effect November 6, 2026. This finding is rejected.

## Important findings

- The B.C. roster omitted all 27 regional districts and Islands Trust. Alberta omitted the eight Métis Settlement local governments. Improvement District No. 349 is historical, not current: Alberta's 2021 municipal-change source says it dissolved May 1, 2021.
- Search failures and confirmed absences disappear from Parquet. A national product needs an explicit coverage/audit table so a consumer can distinguish `found`, `confirmed_absent`, and `not_searched` by institution, document type, and fiscal year.
- `statcan.csd` was incorrectly duplicated as an institution identifier. CD/CSD values belong on geography snapshots and links; an institution may associate with zero, one, or many.
- The B.C. scrape contains weak synthesized titles (`Download`, raw URLs), unknown asset roles, missing preferred assets, and no geometry bytes in the current release. These must remain visible as quality limitations rather than implied completeness.
- Daajing Giids demonstrates the need for sourced name history. Lloydminster demonstrates that a government's physical jurisdiction can cross provincial CSD parts.
- National expansion cannot flatten self-governing/treaty governments, bands, reserves, Inuit community governments, Métis settlements, designated authorities, rural districts, local service districts, and municipal corporations into one legal class.

## Simplified target

Keep the existing release-scoped tables, with one institution per legal entity and orthogonal broad type, government level, and source-specific legal form. Add or plan:

- effective-dated name history with instrument citations;
- explicit succession events for amalgamation, dissolution, restructure, and territorial changes;
- geography-link match method, confidence, notes, and source-dated vintages;
- distinct audited statements, SOFI, annual reports, and financial returns;
- a release coverage table recording found/absent/unsearched states; and
- one stable upstream-key-backed canonical-ID registry shared by all adapters.

## Adjudicated factual corrections

- shíshálh Nation is ISC band **551**, confirmed from the current ISC First Nations Location service. Fable's reference to band 555 was incorrect.
- The District of Okanagan Falls remains `proposed` at the 2026-08-21 release date and activates 2026-11-06, confirmed by B.C. OIC 262/2026 and the provincial incorporation page.
- Improvement District No. 349 is correctly historical: it dissolved 2021-05-01 rather than being a missing current municipality.
