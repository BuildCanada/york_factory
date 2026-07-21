# Series (dashboard time series)

Frontend handoff spec for the economy-dashboard charts. One request returns the full
time series for one measure, grouped by jurisdiction (country / aggregate). Unpaginated
by design: responses are bounded (~10 jurisdictions × ~30 annual points, or 1
jurisdiction × a few hundred monthly points).

No authentication. CORS-enabled. Cacheable (see [Caching](#caching)).

## `GET /api/v1/kpis/series`

**Query parameters:**

| Param | Required | Description |
|---|---|---|
| `measure` | yes | Measure slug (see [catalog](#measure-catalog)). `404` if unknown. |
| `jurisdictions` | no | Comma-separated jurisdiction slugs (e.g. `ca,united-states,g7`). Defaults to every jurisdiction that has data for the measure. |
| `from` | no | Inclusive lower year bound (e.g. `2000`). Applies to the calendar year for monthly measures too. |
| `to` | no | Inclusive upper year bound. |

## Response shape

```json
{
  "data": {
    "measure": {
      "slug": "gdp-per-capita-ppp",
      "name": "GDP per capita, PPP (constant 2021 international $)",
      "description": "…",
      "category": "economy",
      "frequency": "annual",            // "annual" or "monthly" — determines point shape
      "higher_is_bad": false,           // true = rising line is bad (e.g. CPI); use for up/down styling
      "unit": {
        "symbol": "intl_$",             // display label for the y-axis
        "kind": "absolute",             // absolute | ratio | rate
        "base_unit": "dollars",
        "scale": 1.0,
        "currency_code": null,
        "denominator_unit": null,
        "denominator_scale": null
      }
    },
    "series": [
      {
        "jurisdiction": { "slug": "ca", "code": "CA", "name": "Canada", "level": "federal" },
        "computed": false,              // true only for the G7 average (we compute it; style as dashed/secondary)
        "points": [ /* see below — sorted ascending, no null values */ ]
      }
    ]
  },
  "meta": {
    "source": {                         // for the "Source: …" chart footer
      "name": "econ_worldbank_gdp_per_capita_ppp",
      "url": "https://api.worldbank.org/v2/…",
      "last_fetched_at": "2026-07-09T14:31:02.113Z"
    },
    "year_range": [1990, 2024]          // [min, max] measurement year across the response
  }
}
```

`series` is sorted by jurisdiction name. Points are sorted ascending in time and never
contain `null` values — gaps in a series are simply missing points, so use a
gap-aware line (don't interpolate across missing years unless intended).

### Point shape depends on `measure.frequency`

**Annual** (`frequency: "annual"`) — one point per calendar year:

```json
{ "year": 2024, "value": 56706.82 }
```

**Monthly** (`frequency: "monthly"`) — one point per month, `date` is the first of the
month, ISO 8601:

```json
{ "date": "2026-04-01", "value": 2352903.0 }
```

Branch on `data.measure.frequency`, not on point key sniffing.

## Measure catalog

Live measures in the `economy` category. All annual measures carry 9 series (Canada,
US, UK, France, Germany, Italy, Japan, OECD average, G7 average); monthly measures are
Canada-only. Data refreshes at most weekly (Mondays).

### GDP — dual source, display both (evaluation in progress)

We are evaluating switching GDP to Canadian sources because they are far more
real-time. **For now the GDP chart should display both Canada series together** so we
can see if it makes sense:

| Slug | Frequency | Unit | Coverage | Freshness |
|---|---|---|---|---|
| `gdp-per-capita-ppp` | annual | intl_$ (PPP, per capita) | 9 jurisdictions, 1990– | trails ~1–2 years (World Bank) |
| `gdp-growth-annual` | annual | % | 9 jurisdictions, 1961– | trails ~1 year (World Bank) |
| `gdp-monthly-canada` | monthly | $M (chained 2017 CAD, millions) | Canada only, 1997– | ~60-day lag (StatCan) |

Suggested GDP chart: two requests, overlaid —

```
GET /api/v1/kpis/series?measure=gdp-per-capita-ppp&jurisdictions=ca
GET /api/v1/kpis/series?measure=gdp-monthly-canada
```

⚠️ The two series are **not in the same unit**: World Bank is per-capita PPP
international dollars; StatCan is the total real GDP level in millions of chained-2017
CAD (~2,350,000 = $2.35T annualized). Overlaying raw values needs either a dual y-axis
or indexing both to a common base year (e.g. 2017 = 100). If neither reads well, tell
us — the backend can add a directly comparable series instead (e.g. StatCan
year-over-year GDP growth % next to `gdp-growth-annual`).

### CPI essentials — cost of living (monthly, Canada-only)

All are index levels, 2002 = 100, not seasonally adjusted, Feb 1993 – present
(StatCan table 18-10-0004-01). `higher_is_bad: true` on all of them. One request per
measure; suggested chart is a multi-line overlay of the categories (they share the
same unit and scale, so a single y-axis works), with `cpi-all-items` as the reference
line.

| Slug | Category |
|---|---|
| `cpi-all-items` | All-items (headline reference) |
| `cpi-food` | Food |
| `cpi-shelter` | Shelter |
| `cpi-rent` | Rent |
| `cpi-clothing-footwear` | Clothing and footwear |
| `cpi-transportation` | Transportation |
| `cpi-gasoline` | Gasoline |
| `cpi-energy` | Energy |

Note these are index levels, not inflation rates. Year-over-year % change can be
derived client-side (`value / value_12_months_earlier - 1`), or ask the backend if you
want it served directly.

### Other annual measures (existing behavior, unchanged)

| Slug | Unit |
|---|---|
| `inflation-cpi-annual` | % (annual CPI inflation, all G7 + OECD) |
| `trade-balance-pct-gdp` | % |
| `labour-productivity-gdp-per-hour` | intl_$_per_hour |

Other dashboard categories (housing, welfare, safety, wellbeing, governance,
infrastructure, international, environment) serve through the same endpoint with the
same shapes. The full slug list lives in `db/seeds/kpis/*_measures.yml` — ask the
backend team for the catalog of any category as it goes live.

## Jurisdiction slugs

For the `jurisdictions` param. Relevant to these charts:

| Slug | Name | Notes |
|---|---|---|
| `ca` | Canada | **not** `canada` |
| `united-states` | United States | |
| `united-kingdom` | United Kingdom | |
| `france`, `germany`, `italy`, `japan` | | |
| `oecd` | OECD (average) | source-provided |
| `g7` | G7 (average) | computed by us; `"computed": true` in the response |

## Caching

Responses send `Cache-Control: max-age=3600, public`, an `ETag`, and `Last-Modified`.
Conditional requests (`If-None-Match` / `If-Modified-Since`) return `304`. Data
changes at most weekly, so client-side caching is safe and encouraged.

## Errors

| Status | Meaning |
|---|---|
| `404` | Unknown `measure` slug — `{ "error": "Not found" }` |
| `200` with empty `series` | Valid measure, but no data matches the filters (e.g. jurisdiction slug with no data for that measure, or an out-of-range `from`/`to`) |
