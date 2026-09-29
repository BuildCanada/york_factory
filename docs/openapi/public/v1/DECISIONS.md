# Decisions for the v1 contract

These are the places where the design (fact-factory `docs/public-interface-design.md`, PR #26) left something open, and what WS-A decided. They were made overnight on 2026-09-28 without review, so each one can be changed. Until launch, changing one is not a breaking change (see README, "Versioning"). Items marked **review** need Brendan's call.

## Scope

1. **Phase 1 only.** WS-A's scope is "every phase 1 operation in §3.2", and WS-L and WS-M add the phase 2 and 3 resources to the spec themselves. So corporations, persons, documents, network, paths, StatCan and `/v1/keys` are not in the spec, not even as stubs. Where later phases matter, enums and descriptions say what arrives later: `search types`, `Predicate`, `EntityClass.person` and the `keys:manage` scope. (There is no `read:persons` scope; see 39.) Stub operations would have become promises in the SDKs.
2. **25 operations.** These are §3.2's phase 1 rows, plus `GET /entities/{id}/spending/unlinked`. §3.4's `linked_only` caveat links to that operation, but the catalogue leaves it out. `GET /v1/changelog` (§9) is left out. It isn't in §3.2, and each release's `changes[]` covers the data stream for now.
3. **Discovery paths are relative to the server.** The server URL is `https://data.buildcanada.com/v1`, so the index is `GET /` and the spec is `GET /openapi.json`. `/.well-known/oauth-protected-resource` lives outside `/v1` and belongs to WS-F.

## File layout and tooling

4. **Path.** The spec is at `docs/openapi/public/v1/openapi.yaml`, which is the design's path. The task brief suggested `openapi/v1.yaml`, but the design wins. The bundle was `public/v1/openapi.json`, as the design specifies. Rails' static file server would serve it with the production one-year cache header, ahead of any route. **WS-D moved it** to `docs/openapi/dist/v1/openapi.json` and serves it through a route (`GET /v1/openapi.json`, `max-age=300`, rate-limited like every operation).
5. **Two linters.** Spectral runs `.spectral.yaml` on the **bundle**. Spectral 6.16 rejects valid OpenAPI 3.1 path items that `$ref` another file. Redocly lints the **split source**, so errors point at the right file and line, and it checks every example. Redocly's CLI also does the bundling.
6. **The dictionary rule is in Ruby, not Spectral.** Spectral's resolver drops keywords next to a `$ref`, and that is where `x-bc-dictionary` sits on most fields. `bin/openapi-check-dictionary` reads the source YAML instead.
7. **Where dictionary terms come from.** The design checks terms against `catalog/dictionary.json` (WS-K2), which doesn't exist yet. `dictionary-terms.json` is a synced list of term names from fact-factory `6b102fe:docs/data-dictionary.yaml`. `bin/openapi-sync-dictionary` refreshes it from either format.
8. **20 terms are pending.** The API needs 20 terms the dictionary doesn't define yet. Examples are `asset_key`, `snapshot_id`, `spending_key`, `measure`, `link_status`, `name_fr`, `redirected_to` and the summary counts. Rather than fail the acceptance check, they are listed in `pending-dictionary-terms.yaml` with proposed definitions for WS-B and WS-K to add. The check fails if a pending term lands in the dictionary without being removed from the list, or if the spec stops using it. `--strict` fails while any term is still pending. **Follow-up:** add these to fact-factory, then run the check with `--strict` in CI.
9. **What counts as a data field.** Data fields are the properties of schemas marked `x-bc-record: true`, which are the fact-bearing objects. Properties that are links, provenance, citations or embedded objects are marked `x-bc-structural: true`. Envelope, meta, release, dataset, usage and `me` schemas describe the API, not the data, so they carry no terms.
10. **The oasdiff gate is off before launch.** `bin/openapi-breaking` reports breaking changes but doesn't fail while `info.version` is a prerelease (`1.0.0-alpha.1`). Setting `1.0.0` turns the gate on. oasdiff 1.32.1 is pinned in CI.
11. **Tests are a plain Minitest file with no Rails.** `test/openapi/public_v1_spec_test.rb` loads only `json_schemer`, which is now in the Gemfile's test group. It runs under `bin/rails test` and standalone in the `openapi` CI job. WS-D can reuse `json_schemer` to validate responses (design D3's fallback).

## Representation

12. **Some values are rendered differently from the dictionary's storage type.** The field's description says so, and the field still names the same term.
    - `fiscal_year` is the label `YYYY-YY` ("2024-25", the start year). The dictionary stores the four-digit start year. This follows §3.4's examples and the §3.9 error text.
    - `verified` is a boolean. The dictionary stores 0 or 1.
    - `recorded_at` is an RFC 3339 timestamp. The dictionary stores a Unix float.
13. **Amounts** match `^-?[0-9]+\.[0-9]{2,6}$`: at least 2 decimals, and up to 6 because the table is decimal(38,6).
14. **Spending keys** are Crockford base32, 26 characters, the same alphabet as ULIDs. They are built from the first 128 bits of sha256(asset_key, acquisition, resource_id, id). The design says only "base32".
15. **`candidates` holds entity gids** rather than bare ULIDs, so every entity reference in the API has the same form. Corporation anchors stay `ca/ised/federal_corporations:<n>`.
16. **Datasets are keyed by the percent-encoded asset key** in the path (`/datasets/sources%2Fca%2Ftbs%2Fproactive_grants`), because keys contain slashes. Every list item carries `links.self`, so clients rarely have to build one.
17. **`values` in `DictionaryTerm`** is always an array of `{value, meaning}`. The YAML dictionary uses both lists and maps.
18. **Enums in responses.** They use `enum` so agents and docs can read them. The versioning policy says new values are additive, so the SDK generators must be configured to tolerate unknown values (WS-J).
19. **Entity `attributes`** is an open object, and only keys allowlisted by WS-B are served. **Decided 2026-09-29:** the school-board `addresses` attribute, and any other address attribute, is not served in v1. It is deferred until someone decides whether organization street addresses belong in the API. WS-B must leave it off the `api.entities` allowlist.
20. **`recipient_postal_code` follows the persons rule (decided 2026-09-29).** People are shown by city, province and FSA only. When a row's recipient occurrence is an individual (`party_kind` is `individual`), the API serves only the FSA: the first 3 characters, uppercased. The same reduction applies to the postal code inside `raw` (`expand=raw`) and in the bulk exports. Organizations keep the full postal code as published. WS-B applies this in `api.spending_records`, and WS-K in the exports.

## Behaviour the spec fixes for WS-D

21. **Spending filters.** `payer=` and `recipient=` on `/spending` take entity IDs and match linked occurrences only. Free-text names go in `q=`. `recipient=` covers recipient, recipients, research_org and principal_investigator.
22. **Summary grouping.** In `/entities/{id}/spending/summary`, `source` is always a grouping key, even when `group_by` leaves it out. Rows also split by currency. Aggregate rows are counted in `meta.aggregated_rows_excluded`, and unlinked occurrences with the entity's name in `meta.unlinked_occurrences`. Blank amounts are counted per row in `amount_missing`.
23. **`/entities/{id}/spending`** returns linked rows only by default. `include_proposed=true` adds proposed links, marked by `link_status`.
24. **`parties[]`** is always on `GET /spending/{id}`, and on list items only with `expand=parties`, to keep list pages small.
25. **Lineage.** `/lineage` takes `direction=predecessors|successors` (default predecessors) and `max_depth` (1 to 10, default 10). It returns steps nearest first.
26. **Relationships.** `/relationships` takes `direction=out|in|both` (default both). Each item says its direction relative to the requested entity.
27. **Search limits.** `/search` pages are 20 by default and 50 at most. These began as the §8.1 person caps; since 39 they are general page limits, the same for every class. The minimum query is 2 characters, and 422 `query_too_broad` otherwise.
28. **Identifier resolution.** `/identifiers/{namespace}/{value}` returns every holder (`matches[]`) rather than picking one, because a BN can be shared after an amalgamation. It returns 404 when nothing holds the identifier.
29. **Units.** `x-bc-units` is `{base, large_page?, count_exact?}`. `count_exact` is **added** to the base, following §3.1's "+2 units". The test checks the base units against §6.1.
30. **Caching.** `x-bc-cache` is `release` for release-pinned data (ETag, immutable when pinned, 304), `short` for `/`, `/openapi.json`, `/releases` and `/releases/latest`, and `none` for `/me*`.
31. **Problems.** `internal_error` (500) is added to §3.9's codes. Problems carry `bulk_url` on 429s ("bulk links in 429s", §8.2), `earliest_release` on `not_yet_published`, `cursor_release` on `release_mismatch`, and `location` on 301.
32. **`GET /me`** works anonymously and reports plan `anonymous` with a daily allowance. `/me/usage` needs `usage:read` and a real caller.
33. **Staging** is `https://data.staging.buildcanada.com/v1`, with `bc_stg_` keys. The design names the key prefix but not the host. **Review:** check that the DNS name is right.

## Changes WS-D made while implementing the contract (1.0.0-alpha.2)

34. **Three auth problem codes.** `account_suspended`, `ip_not_allowed` and `origin_not_allowed` (403) are in the `Problem.code` enum. WS-E's `PublicApiAuthentication` answers with them, and they say more than `insufficient_scope` would.
35. **403 on every keyed operation.** Any key can meet a suspended account, an IP or origin restriction, or a scope the key doesn't hold (`usage:read` on `/me/usage`). The contract had 403 on `/me/usage` only. `/openapi.json` also declares 400, 401 and 403, because it authenticates like the rest.
36. **422 where a query can outgrow its limits.** `listEntities`, `listSpending`, `listEntitySpending` and `getEntitySpendingSummary` declare 422 `query_too_broad`. It is the answer to a statement timeout (design §8.2). (Until fact-factory 6b3034e it was also the answer to `group_by=counterparty` on an entity with more than 50,000 linked rows, computed live; that summary is now precomputed in `api.spending_counterparties`, so the limit is gone.)
37. **Review: `fields` against `required`.** A `fields=` projection leaves out properties that `Entity` and `SpendingRecord` require, so a projected response fails its own schema. WS-D's tests check projected items field by field. The contract should say that `fields` responses are partial (for example, a `Partial<Entity>` schema, or a note on each operation), so SDK generators don't reject them.
38. **`is_latest_revision` is the table's, not the slice's.** fact-factory sets `spending_records.is_latest_revision` per slice (asset_key and acquisition), so an `archive_import` copy of an older revision is the latest of the archive slice, and `latest_revision_only=true` returned it next to the live latest revision. The API serves, and filters on, the flag across the table: a live row keeps fact-factory's flag, and an `archive_import` row is the latest only when fact-factory flags it and no live row of the release has its canonical_id. An agreement only the archive has stays visible. Summaries are unchanged (they never count archive rows).

## People data

39. **Person data is `read:public` (decided 2026-09-29).** Brendan: "Remove many of the restrictions on people, we have already protected their personal information a lot by restricting addresses." So:
    - There is no `read:persons` scope. Person entities, individuals' names, the persons endpoints and person results in MCP are read with `read:public`, anonymously wherever the rest of the API is anonymous. The scope is gone from `x-bc-scopes`, `Me.scopes` and the OAuth scopes, and is not kept as an alias: nothing has launched, so no client holds it.
    - There is no data-terms acceptance step before a key can read people.
    - Persons are listed, searched and filtered like other entities (`class=person` on `/entities` and `/search`, when person entities exist).
    - There are no person-specific rate limits or unit surcharges. Person operations cost the same units as any other operation.
    - **Kept:** the address rule of 19 and 20. A person's address is only ever city, province and FSA, never a street address, and an individual recipient's postal code is served as its FSA. No address keys are served. Also kept are the factual caveats `person_is_clustering` (a person entity is our clustering of records, not a legal identity) and `observed_not_appointed` (`observed_from` is when a filing first showed the role, not the appointment date). Authentication, abuse controls, general rate limits and audit logs are unchanged.

## URLs

40. **Developer docs live at `https://data.buildcanada.com/api` (decided 2026-09-29).** `data.buildcanada.com/` is kept for a future public interactive site, so nothing the API names sits at the root any more. Every docs URL moves under `/api`: pages and Markdown twins (`/docs/...` becomes `/api/...`, including `termsOfService`, `externalDocs`, caveat anchors at `/api/caveats#<code>` and dictionary term pages at `/api/dictionary/<term>`), problem type URIs (`/problems/<code>` becomes `/api/problems/<code>`) and `llms.txt` (`/api/llms.txt`). The API itself stays at `/v1`, MCP at `/mcp`, and OAuth metadata at `/.well-known/...`. Problem type URIs are identifiers, so this is a breaking change once launched; before launch it is not (see 10).
