# Decisions for the v1 contract

These are the places where the design (fact-factory `docs/public-interface-design.md`, PR #26) left something open, and what WS-A decided. They were made overnight on 2026-09-28 without review, so each one can be changed. Until launch, changing one is not a breaking change (see README, "Versioning"). Items marked **review** need Brendan's call.

## Scope

1. **Phase 1 only.** WS-A's scope is "every phase 1 operation in §3.2", and WS-L and WS-M add the phase 2 and 3 resources to the spec themselves. So corporations, persons, documents, network, paths, StatCan and `/v1/keys` are not in the spec, not even as stubs. Where later phases matter, enums and descriptions say what arrives later: `search types`, `Predicate`, `EntityClass.person` and the `keys:manage` scope. (There is no `read:persons` scope; see 39.) Stub operations would have become promises in the SDKs.
2. **25 operations.** These are §3.2's phase 1 rows, plus `GET /entities/{id}/spending/unlinked`. §3.4's `linked_only` caveat links to that operation, but the catalogue leaves it out. `GET /v1/changelog` (§9) is left out. It isn't in §3.2, and each release's `changes[]` covers the data stream for now.
3. **Discovery paths are relative to the server.** The server URL is `https://data.buildcanada.com/v1`, so the index is `GET /` and the spec is `GET /openapi.json`. `/.well-known/oauth-protected-resource` lives outside `/v1` and belongs to WS-F.

## File layout and tooling

4. **Path.** The spec is at `docs/openapi/public/v1/openapi.yaml`, which is the design's path. The task brief suggested `openapi/v1.yaml`, but the design wins. The bundle is `public/v1/openapi.json`, as the design specifies. WS-D decides how the `data.` host routes `/v1/openapi.json`. Rails' static file server would serve it with the production one-year cache header, so WS-D should serve it through a route with `max-age=300` instead.
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
19. **Entity `attributes`** is an open object, and only keys allowlisted by WS-B are served. The address exclusion decided here on 2026-09-29 is **superseded by 41**.
20. **Superseded by 41.** On 2026-09-29 an individual recipient's `recipient_postal_code` was to be cut to its first 3 characters. It is now served as published.

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

## People data

34 to 38 are WS-D's contract changes, on #140.

39. **Person data is `read:public` (decided 2026-09-29).** Brendan: "Remove many of the restrictions on people." So:
    - There is no `read:persons` scope. Person entities, individuals' names, the persons endpoints and person results in MCP are read with `read:public`, anonymously wherever the rest of the API is anonymous. The scope is gone from `x-bc-scopes`, `Me.scopes` and the OAuth scopes, and is not kept as an alias: nothing has launched, so no client holds it.
    - There is no data-terms acceptance step before a key can read people.
    - Persons are listed, searched and filtered like other entities (`class=person` on `/entities` and `/search`, when person entities exist).
    - There are no person-specific rate limits or unit surcharges. Person operations cost the same units as any other operation.
    - **Kept:** the factual caveats `person_is_clustering` (a person entity is our clustering of records, not a legal identity) and `observed_not_appointed` (`observed_from` is when a filing first showed the role, not the appointment date). Authentication, abuse controls, general rate limits and audit logs are unchanged. This entry also kept the address rule of 19 and 20, which is **superseded by 41**.

## URLs

40. **Developer docs live at `https://data.buildcanada.com/api` (decided 2026-09-29).** `data.buildcanada.com/` is kept for a future public interactive site, so nothing the API names sits at the root any more. Every docs URL moves under `/api`: pages and Markdown twins (`/docs/...` becomes `/api/...`, including `termsOfService`, `externalDocs`, caveat anchors at `/api/caveats#<code>` and dictionary term pages at `/api/dictionary/<term>`), problem type URIs (`/problems/<code>` becomes `/api/problems/<code>`) and `llms.txt` (`/api/llms.txt`). The API itself stays at `/v1`, MCP at `/mcp`, and OAuth metadata at `/.well-known/...`. Problem type URIs are identifiers, so this is a breaking change once launched; before launch it is not (see 10).

## Addresses

41. **Addresses and postal codes are served as the source publishes them (decided 2026-09-30).** Brendan: "This data is all public." This supersedes 20 and the address parts of 19 and 39. Every postal code, an individual recipient's included, is served as the source writes it: in `recipient_postal_code`, in `raw` and in the bulk files. Address attributes, such as a school board's `addresses`, are served like any other attribute. Nothing has launched, so this is not a breaking change (see 10). The correctness caveats stay: a person entity is our clustering of records, not a legal identity (`person_is_clustering`); `observed_from` is when a filing first showed a role, not the appointment date (`observed_not_appointed`); and individuals are never matched to organizations.
