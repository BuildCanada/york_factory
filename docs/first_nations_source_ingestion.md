# National First Nations band source adapter

This component produces a dated manifest of First Nation **band governments**. It deliberately does not turn reserves, Indian settlements, municipalities, treaty governments, tribal councils, special districts, or traditional territories into aliases of a band.

## Identity and geography

- A band has a semantic canonical ID under `ca/fn/{slug}` and the preferred external identifier `isc.band_number`.
- A previous manifest may be supplied so the band number preserves the canonical ID when the upstream name changes.
- New semantic-slug collisions receive the deterministic suffix `-band-{band_number}`. The adapter fails if that still collides.
- ISC's most-populated-reserve number and name are retained only as location context. They are not band identifiers or institutions.
- The ISC latitude/longitude represents the First Nation location or administrative-office point. Its intersection with the 2021 Statistics Canada census subdivision is linked only as `headquartered_in`; it does not assert that the band governs the CSD or reserve.
- Treaty governments and self-governing governments need a separate authoritative source and institution classification. This adapter does not infer either status from a band profile.

## Authoritative sources and access constraints

| Source | Use | Access notes |
| --- | --- | --- |
| [ISC First Nations Location](https://open.canada.ca/data/en/dataset/b6567c5c-8339-4055-99fa-63f92114d9e4) | Band number, official upstream names, point, province, parent-band fields, reserve context | Official English and French ArcGIS layers; daily update; paginated defensively; Open Government Licence - Canada |
| [First Nation Profiles](https://services.sac-isc.gc.ca/fnp/main/Index.aspx?lang=eng) | Official profile page, website and contact metadata | Legacy ASP.NET HTML, no documented JSON API; direct `BAND_NUMBER` GET currently works; markup may change |
| [FNFTA documents](https://services.sac-isc.gc.ca/fnp/Main/Search/SearchFF.aspx?lang=eng) | Audited consolidated financial-statement listings, fiscal-year labels, receipt dates and binary URLs | Legacy ASP.NET HTML; a listed row can have `href="#"` and therefore no retrievable document; documents are published in the language received; ISC/CIRNAC state that the First Nation prepares the statements and an independent auditor audits them |
| [Statistics Canada 2021 cartographic boundaries](https://open.canada.ca/data/en/dataset/ef70dc3b-1069-4037-9bce-61f47e628a1d) | Point-in-polygon CSD UID, DGUID and bilingual names/types | English and French ArcGIS layer 9; this is a physical-location association, not territorial jurisdiction |

FNFTA binaries can be PDF or another response type. A later archival stage must content-sniff, checksum, and write them beneath `/Volumes/floppy/york_factory/public_institutions/assets`; it must not trust the URL extension. Rows whose link is `href="#"` and whose receipt status is `Not yet posted` are recorded as explicit scrape gaps, not as downloaded statement works. Schedule-of-remuneration rows are intentionally not imported by this adapter.

The dated 2026-08-27 recovery also reconciles the earlier FNFTA corpus under `/Volumes/floppy/FinancialStatements/financial_statements`. `script/recover_first_nation_fnfta_assets.rb` accepts only a unique band/year PDF whose metadata does not mark it corrupt, whose recorded size matches, and whose bytes have PDF magic. It writes the recovered bytes into the ontology's content-addressed asset root and preserves the legacy file and metadata paths as provenance. Live retries then handle any remaining transient ISC failures. Recovery never treats a processed chunk or remuneration schedule as a consolidated financial statement.

## Running and importing

The default output is immutable and external-drive backed:

```ruby
manifest = Warehouse::InstitutionRelease::FirstNations::SourceAdapter.new(
  release_version: "2026-08-21",
  previous_manifest_path: "/Volumes/floppy/york_factory/public_institutions/sources/first-nations/releases/2026-08-20/manifest.json"
).call

Warehouse::InstitutionRelease::FirstNations::FinancialStatementArchiver.new(
  manifest_path: manifest
).call

Warehouse::InstitutionRelease::FirstNations::ManifestImporter.new(
  release: Warehouse::InstitutionRelease.find_by!(version: "2026-08-21"),
  path: manifest
).import!
```

The adapter refuses to overwrite an existing dated source directory, and the archiver refuses to overwrite its inventory. Successful binaries use content-addressed `sha256/` paths; retrieval failures remain explicit inventory rows. A retry can write a new sidecar by passing `inventory_path:` and that sidecar can be selected with the importer's `asset_inventory_path:`. Use `limit:` only for a clearly marked partial development scrape. The importer adds records to an already-created release so a national release coordinator can combine this source with federal, provincial, municipal, Inuit, Métis, and other components.

For the 2026-08-27 release, FNFTA listed 6,351 downloadable audited statements for 580 of 620 standalone bands. All 6,351 binaries were archived and validated. Forty bands had no downloadable listing; FNFTA showed 64 audited-statement placeholder rows for them as `Not yet posted`. Those are source-availability gaps, not downloader failures.
