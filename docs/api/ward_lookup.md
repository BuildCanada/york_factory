# Postal code → ward lookup — frontend contract

For the "find your ward" input on `/toronto/elections/2026`. One
unauthenticated GET, postal code in, ward out.

**Status: built and tested, not yet live.** See [Before you can call
this](#before-you-can-call-this) — the route 404s on production until
york_factory ships. Build against a local API or wait for the deploy note.

---

## The endpoint

```
GET /api/v1/geo/ward_lookup?postal_code=M4C1S9
```

Public, unauthenticated, no headers required, CORS-enabled. Same namespace as
`geo/boundaries` and `geo/addresses`.

**Base URL:** `https://yorkfactory.buildcanada.com` (dev: `http://localhost:3000`).

Note that `docs/api/README.md` and `docs/api/elections.md` both name
`https://api.buildcanada.com` as the production base — that host currently 404s
on every route, including `/api/v1/elections`. `yorkfactory.buildcanada.com` is
what actually serves. Use it, and flag the discrepancy if the elections page is
pointed at the other one.

### Parameters

| param | required | notes |
| --- | --- | --- |
| `postal_code` | yes | Any spacing or casing. `m4c1s9`, `M4C 1S9`, `M4C-1S9` all work — do **not** normalize or validate client-side, just forward what they typed. |
| `boundary_type` | no | Defaults to `ward`. Only other useful value is `school_board_ward`, and those aren't loaded yet, so ignore it for v1. |

### Status codes

`200` for every answer, **including when we can't find the ward** — an
unplaceable postal code is a result, not an error. Branch on the `reason` field,
never on the status.

`400` only for a request we can't act on: missing/blank `postal_code`, or an
unrecognized `boundary_type`. Body is `{"error": "..."}`. If you see a 400 in
normal use, it's a bug in the caller.

---

## Response — resolved

```json
{
  "postal_code": "M4C 1S9",
  "city": "TORONTO",
  "found": true,
  "reason": "resolved",
  "unverified": false,
  "ward": {
    "geo_uid": "3520005-19",
    "ward_number": 19,
    "name_en": "Beaches-East York",
    "name_fr": null,
    "boundary_type": "ward",
    "census_year": 2021
  }
}
```

## Response — not resolved

Same envelope, `found: false`, `ward: null`:

```json
{
  "postal_code": "K1A 0A9",
  "city": "OTTAWA",
  "found": false,
  "reason": "outside_boundary",
  "unverified": false,
  "ward": null
}
```

## Fields

| field | type | notes |
| --- | --- | --- |
| `postal_code` | `string \| null` | Normalized to `"M4C 1S9"` form. **Null when `reason` is `malformed_postal_code`** — there was nothing to normalize. Safe to echo back to the user otherwise. |
| `city` | `string \| null` | Canada Post's city label, uppercase (`"TORONTO"`, `"SCARBOROUGH"`, `"NORTH YORK"`). Null when the postal code is malformed or unknown. This is *Canada Post's* name, not a jurisdiction — a `"TORONTO"` label doesn't guarantee the code is in Toronto, and `"SCARBOROUGH"` is still Toronto. Use it for display only; use `reason` to decide anything. |
| `found` | `boolean` | Convenience mirror of `reason === "resolved"`. |
| `reason` | `string` | Stable enum, see below. The field to branch on. |
| `unverified` | `boolean` | True where we *couldn't judge*, as opposed to judging them outside. Lets you split "ask them to check what they typed" from "tell them they're outside Toronto" without hardcoding the reason list. |
| `ward` | `object \| null` | Null unless `found`. |
| `ward.ward_number` | `number \| null` | **The integer you route on.** Never null for Toronto municipal wards (1–25). Can be null for school board wards, whose ids are named rather than numbered — so keep the null check if you ever pass `boundary_type`. |
| `ward.name_en` | `string` | e.g. `"Beaches-East York"`. Display name. |
| `ward.name_fr` | `null` | Always null for Toronto wards — the city's open data ships English only. Fall back to `name_en` in FR. |
| `ward.geo_uid` | `string` | Our internal id, `"<csd_uid>-<ward>"`. **Don't parse it and don't route on it** — the format may change. Fine to log. |
| `ward.census_year` | `number` | `2021`. This is a data-warehouse load tag, **not** the ward model's vintage (the boundaries are the 2018 25-ward model). Don't display it. |

## `reason` values

Stable strings. Copy differs per case:

| `reason` | `found` | `unverified` | means | UI intent |
| --- | --- | --- | --- | --- |
| `resolved` | `true` | `false` | We placed them in a ward | Show the ward |
| `malformed_postal_code` | `false` | `true` | Not a postal code at all | "That doesn't look like a postal code" — inline validation, let them retry |
| `unknown_postal_code` | `false` | `true` | Well-formed, not in our data | "We don't recognize that postal code" — softer, it may be real and new |
| `outside_boundary` | `false` | `false` | Geocoded fine, no ward contains it | "Looks like you're outside Toronto" — this is a real answer, don't apologize |
| `boundary_data_unavailable` | `false` | `true` | No ward boundaries loaded | Generic failure, and it's on us. Don't blame their input. Treat like a 500 for logging/alerting. |

Treat an unrecognized `reason` as a generic failure rather than crashing — we may
add cases (e.g. when school board wards land).

---

## How certain this is — please don't overstate it

**Do not hard-redirect on the result.**

A postal code's stored point is the centroid of its delivery points. A code that
straddles a ward line can resolve to the neighbouring ward. We measured
*coverage* at 99.89% of Toronto's ~51k `M` postal codes resolving to some ward —
but that number says nothing about how many resolved to the *wrong* one, and
ward lines are far more numerous than city lines, so the wrong-ward rate is
meaningfully higher than the 0.08–0.9% we measured for municipal boundaries.

So:

- Present it as a best guess — **"Looks like you're in Ward 19, Beaches-East York"** — not a fact.
- Always offer a way to browse all wards next to the result, so someone we placed wrong can self-correct.
- Never auto-navigate. Let them click through to `/toronto/elections/2026/wards/19`.

There is currently no way for the API to tell you a result is borderline. If you
want "this postal code sits on the edge of Wards 19 and 14", ask — we can add an
optional `distance_to_boundary_m`, it was deferred out of v1.

## Caching

The answer depends only on the postal code, so the API sets long cache headers
and you can safely cache through a Next route with ISR:

- `resolved` / `outside_boundary` → `max-age=86400, public`
- `unknown_postal_code` → `max-age=3600, public` (a real new code may show up in a later import)
- `boundary_data_unavailable` → `no-store` (our outage; never cache it)

Respect these rather than setting your own — the short TTL and `no-store` cases
exist for a reason.

---

## Types

```ts
type WardLookupReason =
  | "resolved"
  | "malformed_postal_code"
  | "unknown_postal_code"
  | "outside_boundary"
  | "boundary_data_unavailable";

type Ward = {
  geo_uid: string;        // internal — do not parse or route on
  ward_number: number | null;
  name_en: string;
  name_fr: string | null;
  boundary_type: "ward" | "school_board_ward";
  census_year: number;    // load tag, not vintage — do not display
};

type WardLookupResponse = {
  postal_code: string | null;
  city: string | null;
  found: boolean;
  reason: WardLookupReason;
  unverified: boolean;
  ward: Ward | null;
};

type WardLookupError = { error: string };  // 400 only
```

## Sketch

```ts
async function lookupWard(postalCode: string): Promise<WardLookupResponse> {
  const url = new URL(`${API_BASE}/api/v1/geo/ward_lookup`);
  url.searchParams.set("postal_code", postalCode);  // send it raw

  const res = await fetch(url, { next: { revalidate: 86400 } });
  if (!res.ok) throw new Error(`ward_lookup ${res.status}`);  // 400 = our bug
  return res.json();
}
```

```tsx
switch (result.reason) {
  case "resolved":
    return (
      <>
        <p>Looks like you’re in <strong>Ward {result.ward!.ward_number}</strong>,
           {" "}{result.ward!.name_en}.</p>
        <Link href={`/toronto/elections/2026/wards/${result.ward!.ward_number}`}>
          See your candidates
        </Link>
        <Link href="/toronto/elections/2026/wards">Not right? Browse all 25 wards</Link>
      </>
    );
  case "malformed_postal_code":
    return <FieldError>That doesn’t look like a postal code.</FieldError>;
  case "unknown_postal_code":
    return <FieldError>We don’t recognize that postal code. Double-check it?</FieldError>;
  case "outside_boundary":
    return <Note>That postal code looks like it’s outside Toronto.</Note>;
  default:  // boundary_data_unavailable + anything new
    return <Note>We can’t look that up right now. Try again shortly.</Note>;
}
```

## Verified behaviour

Every row below was run against the real API and the full ~900k-row postal table:

| input | status | `reason` | result |
| --- | --- | --- | --- |
| `M4C1S9` | 200 | `resolved` | Ward 19, Beaches-East York |
| `m5v 3l9` | 200 | `resolved` | Ward 10, Spadina-Fort York |
| `M4C-1S9` | 200 | `resolved` | Ward 19 (spacing/casing tolerated) |
| `K1A0A9` | 200 | `outside_boundary` | `ward: null` |
| `M4C9Z9` | 200 | `unknown_postal_code` | `ward: null` |
| `garbage` | 200 | `malformed_postal_code` | `ward: null` |
| *(no param)* | 400 | — | `{"error": "postal_code is required"}` |

Toronto has 25 wards, numbered 1–25 with no gaps, all with geometry — so
`/wards/1` … `/wards/25` are the complete set of valid routes.

---

## Before you can call this

As of this writing, on production:

- `GET /api/v1/geo/ward_lookup` → **404** (route not deployed)
- `GET /api/v1/geo/boundaries?boundary_type=ward&province_code=35` → **`count: 0`** (no ward geometry loaded)

Both are pending on the york_factory side: the deploy, plus a one-time manual
ingest of the Toronto ward shapefile (the source is `fetch_frequency: "manual"`,
so it doesn't run itself). Until then the endpoint would answer
`boundary_data_unavailable` even once routed — which is exactly why that reason
exists, so you can build and ship the UI against it now and have it start
working when the data lands.

You can verify readiness yourself at any time with the boundaries call above —
expect `count: 25`.
