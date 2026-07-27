# Elections API — front-end spec

Reference for building an election candidate page. Written against the
Brampton 2026 municipal election (`/elections/brampton/2026`), with a
Hamilton section below; the same endpoints and payload shape serve Toronto
(`toronto-2026`) and any election added later, so build against the payload,
not against one city's specifics.

- Base URL: `https://api.buildcanada.com` (dev: `http://localhost:3000`)
- Read endpoints are public — no token, CORS-enabled (`CORS_ORIGINS`)
- Response bodies are JSON; dates are `YYYY-MM-DD`

---

## Endpoints

### `GET /api/v1/elections`

Every tracked election, newest election date first. No races or candidates —
use it to build a list/switcher.

```json
{
  "data": [
    {
      "slug": "brampton-2026",
      "name": "Brampton 2026 General Municipal Election",
      "kind": "municipal",
      "election_date": "2026-10-26",
      "nomination_close_date": "2026-08-21",
      "jurisdiction": { "name": "City of Brampton", "slug": "brampton", "level": "municipal" },
      "updated_at": "2026-07-27T15:12:18.956Z"
    }
  ]
}
```

### `GET /api/v1/elections/:slug`

The full election with every race and candidate. **This is the only call
`/elections/brampton/2026` needs.**

- Slug for this page: **`brampton-2026`** (`/api/v1/elections/brampton-2026`)
- `404 {"error":"Not found"}` for an unknown slug
- One response is currently ~21 races / ~71 candidates — a few tens of KB.
  Fetch once and filter client-side; there are no query params for
  filtering by office or ward.

Same top-level object as the index, plus `races`:

```json
{
  "slug": "brampton-2026",
  "name": "Brampton 2026 General Municipal Election",
  "kind": "municipal",
  "election_date": "2026-10-26",
  "nomination_close_date": "2026-08-21",
  "jurisdiction": { "name": "City of Brampton", "slug": "brampton", "level": "municipal" },
  "updated_at": "2026-07-27T15:12:18.956Z",
  "races": [
    {
      "office_type": "trustee",
      "district_type": "school_board_ward",
      "district_number": 1,
      "district_name": "Wards 1, 5",
      "ward_numbers": [1, 5],
      "office_body": "Peel District School Board",
      "candidates": [
        {
          "full_name": "Green, David",
          "first_name": "David",
          "last_name": "Green",
          "status": "active",
          "nomination_date": "2026-05-01",
          "withdrawn_date": null,
          "website": "http://www.electdavid.ca",
          "social_links": [{ "name": "web", "url": "http://www.electdavid.ca" }],
          "photo_url": null,
          "photo_attribution": null
        }
      ]
    }
  ]
}
```

### `GET /api/v1/elections/:slug/pledges/eligibility?postal_code=…`

Checks a postal code against the region **before** asking for an email, so
someone outside is told up front. No side effects, no subscriber created.

```json
{
  "eligible": true,
  "reason": "city_match",
  "unverified_postal_code": false,
  "gated": true,
  "region_name": "City of Hamilton",
  "postal_code": "L8P 1A1",
  "city": "HAMILTON"
}
```

- Accepts any format (`l8p1a1`, `L8P 1A1`); `postal_code` echoes the normalized form.
- `gated: false` means this region has no residency rule and accepts everyone.
- `unverified_postal_code: true` means **we couldn't judge**, not that they're
  outside — show "check that postal code", not "you're not eligible".

### `POST /api/v1/elections/:slug/pledges`

Params: `email` (required), `postal_code`, `region` (required), `name`.

`region` is free text scoping the pledge — a ward key like `"ward-5"` /
`"wards-1-5"`, or the jurisdiction slug for a city-wide pledge. It's what
`GET /pledges` tallies by. **A missing `region` is a `422`** — the client picks it.

**Eligible** → `201` (or `200` re-pledging, which updates region and timestamp):

```json
{ "region": "wards-1-5", "pledged_at": "…", "share_token": "v17vlb4auy",
  "name": "Jane Voter", "region_count": 12 }
```

**Not eligible** → `200` with no pledge recorded. The email is still kept as a
newsletter subscriber, so treat this as "subscribed, redirect to explore":

```json
{ "outside_region": true, "outside_toronto": false, "region_name": "City of Brampton",
  "reason": "city_mismatch", "unverified_postal_code": false,
  "subscribed": true, "name": "Otto Outsider" }
```

`outside_toronto` is retained only for the Toronto pledge form that shipped
against it, and is `true` only for Toronto. **New clients should read
`outside_region`.**

### `GET /api/v1/elections/:slug/pledges`

`{ "data": { "total": 37, "by_region": { "wards-1-5": 12, … } } }`

### Eligibility reasons

| `reason` | Eligible | Meaning |
| --- | --- | --- |
| `city_match` / `inside_boundary` | yes | Postal code resolves inside the region |
| `city_mismatch` / `outside_boundary` | no | Resolves to somewhere else — genuinely outside |
| `fsa_match` | yes | Unknown code, but the region owns the whole FSA (Toronto's `M`) |
| `unknown_postal_code` | no | Well-formed but not in our postal table — **unverified** |
| `malformed_postal_code` | no | Not a Canadian postal code — **unverified** |
| `no_postal_code` | yes | None submitted (carried-over behaviour, see below) |
| `no_rule` | yes | Region has no residency rule configured |
| `postal_data_unavailable` | yes | No postal data loaded in this environment |

Residency is judged from the postal code's city (province-scoped), upgrading
automatically to a point-in-polygon test against the census-subdivision
boundary once those are loaded. Amalgamated communities count as their city — a
Dundas or Binbrook address is a Hamilton address; Scarborough and Etobicoke are
Toronto. Neighbours that share a postal range are correctly excluded: an
Oakville `L6H` code cannot pledge in Brampton.

Two behaviours worth knowing before you build the form:

- **A blank `postal_code` is still accepted** (`no_postal_code`) — carried over
  from the Toronto flow, where ward-scoped pledge links never collected one. If
  the form always sends one this never fires, but it does mean the gate can be
  skipped by omitting the field. Say the word and we'll close it.
- **Someone can pledge in a region they don't live in only if we can't verify
  them** — `unknown_postal_code` and `malformed_postal_code` are rejections, but
  `postal_data_unavailable` fails open by design (rejecting every real resident
  because an import didn't run is the worse failure).

---

## Field reference

### Race

| Field | Type | Notes |
| --- | --- | --- |
| `office_type` | enum | `mayor`, `councillor`, `trustee` (`mp`/`mpp` exist for future federal/provincial elections) |
| `district_type` | enum | `at_large`, `ward`, `school_board_ward`, `riding`, `district` |
| `office_body` | string \| null | The body being elected to. `null` for mayor. Brampton uses it to separate the city-council seat from the regional-council seat in the same district — **treat `(office_type, office_body, district_number)` as the race identity, not `district_number` alone.** |
| `district_number` | int \| null | Lowest ward in the district (`1` for "Wards 1, 5"). `null` for `at_large`. Use it for ordering, not for display. |
| `district_name` | string \| null | Display label for the district: `"Wards 1, 5"` (Brampton), `"Ward 3"` (Hamilton), the ward's name (Toronto). `null` for `at_large` races. |
| `ward_numbers` | int[] \| null | Every ward the district covers: `[1, 5]`. **`null` for every `at_large` race** (they cover the whole city) and for Toronto, whose single-ward races carry the ward in `district_number`. Drive the ward filter off this. |
| `candidates` | array | Sorted by last name, then first name (case-insensitive) |

Races arrive sorted: mayor → councillor → trustee, then by `office_body`
alphabetically, then by `district_number`. Rendering them in the order given
produces the right page; the office-body grouping falls out of it.

### Candidate

| Field | Type | Notes |
| --- | --- | --- |
| `full_name` | string | As published — **`"Last, First"`**, e.g. `"Dhaliwal, Avi"`. Use `first_name`/`last_name` to render, not this. |
| `first_name` | string \| null | `null` for mononymous candidates (`"Gursimranjit Singh"`) |
| `last_name` | string \| null | |
| `status` | enum | `active` \| `withdrawn` |
| `nomination_date` | date \| null | Date the nomination was filed. **Always `null` for Hamilton** — its page publishes no dates. |
| `withdrawn_date` | date \| null | **Always `null` for Brampton and Hamilton** — neither city publishes one. Populated for Toronto. |
| `website` | string \| null | **Always `null` for Hamilton** — its page publishes no websites or socials. |
| `social_links` | array | `[{ "name", "url" }]`, ordered as published. Always `[]` for Hamilton. |
| `photo_url` | string \| null | Admin-reviewed portrait. **`null` for every Brampton and Hamilton candidate today** — plan for a placeholder. |
| `photo_attribution` | string \| null | Display alongside `photo_url` when present |

`social_links[].name` observed to date: `web`, `facebook`, `instagram`,
`tiktok`, `twitter`. Treat it as an open vocabulary — fall back to a generic
link icon on an unknown name rather than dropping the link.

Candidate email and phone are collected but **deliberately not exposed** by
this API. Hamilton's emails aren't even collected — its page obfuscates them
via Cloudflare specifically to stop harvesting, and we honour that.

### Gotchas

- **URLs are unnormalized.** Brampton publishes `http://` (not `https://`)
  and inconsistent casing on emails. Render as-is or normalize client-side;
  use `rel="noopener noreferrer"` on outbound links.
- **`district_number` is not a ward.** `district_number: 1` on a Brampton
  councillor race means "the district whose lowest ward is 1", i.e. wards
  1 and 5. Never print it as "Ward 1".
- **`updated_at` is the election row's timestamp**, not a candidate-change
  marker. It does not move when a candidate is added, so don't use it for
  cache invalidation.

---

## Brampton 2026 specifics

Voting day **October 26, 2026**; nominations close **August 21, 2026 at 2pm**
(so the list is still growing).
Brampton has 10 wards paired into 5 districts, and voters in each district
elect *both* a city councillor and a regional councillor.

21 races (counts as of the July 27, 2026 scrape — they grow during the
nomination window):

| Office | `office_body` | Districts | Candidates |
| --- | --- | --- | --- |
| Mayor | `null` (at-large) | 1 | 7 |
| Councillor, City | Brampton City Council | Wards 1,5 · 2,6 · 3,4 · 7,8 · 9,10 | 24 |
| Councillor, Regional | Region of Peel Council | Wards 1,5 · 2,6 · 3,4 · 7,8 · 9,10 | 20 |
| Trustee | Peel District School Board | Wards 1,5 · 2,6 · 3,4 · 7,8 · 9,10 | 13 |
| Trustee | Dufferin-Peel Catholic DSB | Wards 1,3,4 · 2,5,6 · 7,8,9,10 | 6 |
| Trustee | Conseil scolaire Viamonde | at-large | 0 |
| Trustee | Conseil scolaire catholique MonAvenir | at-large | 1 |

Suggested page labels (the API gives you the parts, not the sentence):

- Mayor → **"Mayor"**
- `councillor` + `Brampton City Council` → **"City Councillor — {district_name}"**
- `councillor` + `Region of Peel Council` → **"Regional Councillor — {district_name}"**
- `trustee` → **"{office_body} Trustee"** + `district_name` when present

### Filter by ward

Brampton's own page offers a 1–10 ward filter. Implement it as: show a race
when `ward_numbers` includes the selected ward, plus every `at_large` race
(mayor, the two French-board trustees). A single ward selection surfaces
7 races: mayor, city councillor, regional councillor, one PDSB trustee, one
DPCDSB trustee, and the two French boards.

### States to design for

- **Race with zero candidates.** Real today (Conseil scolaire Viamonde).
  Render the race with an empty-state line, don't hide it — an uncontested
  or unfiled race is information.
- **Withdrawn candidates.** `status: "withdrawn"`, no date. Brampton keeps
  them listed; mirror that — show them with a "Withdrawn" marker rather than
  filtering them out, and sort/de-emphasize as the design prefers.
- **Mononymous candidates.** `first_name: null`. Render `last_name` alone.
- **No photos.** Every `photo_url` is `null` today.

---

## Hamilton 2026 specifics — `/api/v1/elections/hamilton-2026`

Same voting day and nomination deadline as Brampton. Hamilton has **15 wards**,
one councillor each — no paired districts and no regional council, so
`office_body` is `null` for every councillor race and `district_number` **is**
the ward number. Trustee districts do group wards.

38 races, 85 candidates (as of the July 27, 2026 scrape):

| Office | `office_body` | Districts | Candidates |
| --- | --- | --- | --- |
| Mayor | `null` (at-large) | 1 | 8 |
| Councillor | `null` | Wards 1–15, one race each | 51 |
| Trustee | Hamilton-Wentworth District School Board | 11 districts (some paired, e.g. Wards 5, 10) | 13 |
| Trustee | Hamilton-Wentworth Catholic District School Board | 9 districts | 10 |
| Trustee | Conseil scolaire Viamonde | at-large | 2 |
| Trustee | Conseil scolaire catholique MonAvenir | at-large | 1 |

Suggested labels: mayor → **"Mayor"**; councillor → **`district_name`**
(`"Ward 7"`); trustee → **"{office_body} Trustee"** + `district_name`.

Ward filter: same rule as Brampton, over wards 1–15.

Hamilton-specific notes:

- **Three trustee races have zero candidates** (HWDSB Ward 1, HWDSB Ward 13,
  HWCDSB Wards 8, 14). Design the empty state — it's not hypothetical here.
- **Board names are normalized.** The page says "English Public" / "English
  Separate"; the API returns the official board names above, so a board reads
  the same across Hamilton, Brampton, and Toronto.
- **No dates, websites, socials, or withdrawals.** Hamilton's page publishes
  only name, address, phone, and email — so `nomination_date`,
  `withdrawn_date`, `website` are `null` and `social_links` is `[]`. Every
  candidate is `active`.

---

## Freshness

Candidate lists are scraped from each city's page — Toronto's JSON feeds,
[Brampton's candidate listing](https://www.brampton.ca/EN/City-Hall/Election/Candidates/Pages/candidateListing.aspx),
[Hamilton's candidate page](https://www.hamilton.ca/city-council/municipal-election/candidates-third-party-advertisers/candidates)
— **once nightly at 00:00 UTC** (8pm ET) and upserted; unchanged pages dedupe
on checksum and write nothing. So the API is at most ~24h behind the city, and a
candidate who filed this afternoon may not appear until tonight. Don't promise
real-time in copy ("updated daily" is accurate).

Candidates are never deleted by a scrape. If the city drops someone from the
page without marking a withdrawal, their row persists with a stale internal
`last_seen_at` (not currently exposed).

**Hand-maintained elections don't follow that cadence at all.** Where a city's
list can't be scraped (Ottawa — the site is behind a bot challenge), the
election has no source and its races and candidates are entered and edited in
`/admin/elections`. Those change when someone updates them, not nightly, and
the payload shape is identical either way — so the front end needs no special
casing, but "updated daily" isn't a promise you can make for them.

Responses send no cache headers today — cache at the CDN/client layer as you
see fit; nightly data tolerates a long TTL.

---

## Not built / open decisions

1. **Ward-level eligibility isn't available.** The gate answers "do you live in
   this city", not "which ward are you in", so the form still has to ask the
   pledger to pick their district. Deriving the ward from a postal code needs
   ward boundaries loaded (`ward_*` boundary sources) — ask if you want it.
2. **No per-candidate endpoint.** Deep-linking a candidate means anchoring
   within the election payload (`full_name` is unique within a race).
3. **No candidate-level freshness signal.** If cache invalidation or a
   "last updated" line is needed, ask for `last_seen_at` (or an
   election-level `candidates_updated_at`) to be exposed.
4. **Photos need an admin pass.** Portraits come from admin-reviewed
   suggestions in `/admin/elections/:id`; none have been reviewed for
   Brampton or Hamilton.
5. **Withdrawal dates are unavailable** for Brampton and Hamilton, and won't be
   without a second source. Hamilton publishes no withdrawals at all, so a
   candidate who withdraws simply disappears from the page (and keeps their
   last-known row here).
