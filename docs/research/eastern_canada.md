# Eastern Canada municipal source inventory

Research date: 2026-08-21

This note inventories primary sources for an institution-release adapter covering
Ontario, Quebec, New Brunswick, Prince Edward Island, and Newfoundland and
Labrador. It is deliberately separate from the release implementation so that the
source and modelling decisions can be reviewed before an importer is coupled to
them.

## Conclusions that affect the ontology

1. **A current municipal roster is not a predecessor history.** Ontario publishes
   restructuring orders/activity; Quebec publishes machine-readable territorial
   transactions; New Brunswick's 2023 reform needs regulation schedules plus
   historical boundary layers. PEI and Newfoundland and Labrador generally require
   orders, gazettes, or earlier snapshots. A renamed continuing corporation keeps
   its canonical ID; a dissolved or newly constituted corporation gets its own ID
   and effective-dated `succeeds` edges.
2. **Do not infer legal form from a name.** Ontario explicitly says that words such
   as city, county, town, township, village, and region do not establish tier. Keep
   the source's legal designation and tier as separate fields.
3. **Not every local public body is a municipality.** New Brunswick rural districts
   are administered by the provincial minister with elected advisory councils.
   Newfoundland and Labrador local service districts are also distinct from
   incorporated municipalities. Newfoundland and Labrador Inuit Community
   Governments must be typed as Inuit governments even though the province lists
   them in the same PDF as towns and cities.
4. **A StatsCan CSD is an association, not the municipal identity.** The 2021 SGC
   is a frozen statistical classification. It predates New Brunswick's 2023 reform,
   Newfoundland and Labrador's current legislation, and later municipal changes.
   Some service districts do not map one-to-one to a CSD. Store the StatsCan CSD
   identifier only when the match is evidenced, and retain the provincial legal
   boundary/code independently.
5. **Financial returns are not necessarily audited statements.** Ontario FIR data
   and Quebec open financial data are valuable normalized returns. They must not be
   labelled as the municipality's signed audited-statement PDF unless the retrieved
   asset is that document. New Brunswick's annual report is required to include
   audited statements, while PEI centrally publishes submitted statements.
6. **Current geography schema needs a generalization before ingesting legal
   provincial boundaries.** `institution_geography_snapshots.census_year` is
   mandatory and canonical IDs are derived from it. That works for StatsCan 2021
   geography, but not a GeoNB boundary effective 2023-01-01 or a current provincial
   KMZ. Either keep provincial geometries out of v1, or add a `vintage_on`/source
   snapshot concept that is not called a census year. Include `code_system` in the
   geography uniqueness key.
7. **The current local-level enum does not precisely express province-administered
   rural/service districts.** Do not call them `municipal` merely to fit the enum.
   Use `other` with an exact `legal_form` for a shallow release, and consider a
   future `local_service_area` level or an orthogonal `governance_form` field.

## Common federal geography sources

Use the [Standard Geographical Classification (SGC) 2021](https://www.statcan.gc.ca/en/subjects/standard/sgc/2021/index)
classification and its CSV resources for the frozen 2021 CD/CSD identifiers. The
[2021 Census Subdivision Boundary File](https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/index-eng.cfm)
is the matching geometry source.

For changes after that vintage, ingest the [Interim List of Changes to Municipal
Boundaries, Status, and Names](https://www150.statcan.gc.ca/n1/en/catalogue/92F0009X).
The list includes gaining and losing CSD identifiers, change codes, and effective
dates. The current page warns that it contains changes processed from information
received and therefore may not contain every change. It is a crosswalk and
longitudinal-analysis aid, not a substitute for provincial legal evidence.

Recommended identifier schemes:

- `statscan.sgc2021.csd`
- `statscan.sgc2021.cd`
- `on.mmah` only if Ontario later supplies a durable identifier (the current roster
  does not)
- `qc.code-geographique`
- `nb.local-government` only after confirming the value is a durable provincial
  identifier rather than a publication row number or reform-era label
- province-specific source IDs for PEI and Newfoundland and Labrador only after
  their semantics and persistence are documented

## Ontario

### Roster, websites, and legal form

- Human-readable authority: [List of Ontario municipalities](https://www.ontario.ca/page/list-ontario-municipalities).
  It reports 444 municipalities and identifies each as upper-, lower-, or
  single-tier.
- Machine-readable catalogue record: [Municipalities](https://data.ontario.ca/dataset/municipalities).
- Current English CSV at research time:
  [municipalities_-_en_2026-0526.csv](https://data.ontario.ca/dataset/62e83cbc-0731-4d66-abdc-2f2b31bcd76c/resource/6783a586-6b05-4a73-9663-e60a6963c91e/download/municipalities_-_en_2026-0526.csv).
- Current French CSV at research time:
  [municipalities_-_fr_2026-0526.csv](https://data.ontario.ca/dataset/62e83cbc-0731-4d66-abdc-2f2b31bcd76c/resource/7860ed79-6ed5-41dd-b446-6d8e5d0d8d42/download/municipalities_-_fr_2026-0526.csv).
- Discover resources through the CKAN endpoint
  `https://data.ontario.ca/api/3/action/package_show?id=municipalities`; do not
  permanently hard-code the dated download filename.

The CSV has three fields: municipality, municipal status, and geographic area. The
municipality value is HTML linking to the official website. Parse the anchor's text
and `href`; do not retain the HTML as the name. There is no explicit stable
municipal identifier. The separate English and French resources are authoritative
upstream translations and may populate both names where the rows can be matched
without fuzzy guessing.

Treat upper/lower membership as an `administrative_parent` relationship only where
the source association is explicit. A single-tier municipality has no upper-tier
municipal parent. Do not infer that a county is upper tier from the word “County.”

### Geography and predecessors

- [Lower-tier and single-tier municipal boundaries](https://data.ontario.ca/en/dataset/lower-tier-and-single-tier-municipal-boundaries)
- [Municipal Boundary - Lower and Single Tier resource](https://data.ontario.ca/dataset/municipal-boundaries/resource/82ce5025-bb37-43bd-8791-2a5eebed329a)
- [Municipal restructuring](https://www.ontario.ca/page/municipal-restructuring)

The restructuring page links an activity summary for annexations and amalgamations
since 1996 and identifies effective dates and Ontario Gazette publication dates.
Capture the implementing order/Gazette source for every predecessor edge. An
annexation of only part of a municipality is a territorial event; it does not imply
that one institution succeeds the other.

The provincial boundary catalogue is the better source for the current legal/tier
shape. StatsCan CSD is the common national association. Upper-tier municipalities
usually require a CD or provincial upper-tier layer rather than a CSD, and some
Ontario geographic areas do not express municipal hierarchy by containment alone.

### Financial and annual reports

- Catalogue: [Financial Information Return (FIR) for municipalities](https://data.ontario.ca/en/dataset/financial-information-return-fir-for-municipalities)
- Year-index application: [FIR Data by Year](https://efis.fma.csc.gov.on.ca/fir/MultiYearReport/MYCIndex.html)

The FIR is the province's standardized annual collection under Municipal Act,
2001, s. 294(1). It has data from 1977 and CSV by year from 2000. Ingest it as a
financial-return dataset/source, not as a signed audited-statement asset. No central
provincial archive of all municipal audited PDFs was identified; discover those on
each official municipal website and preserve both the landing page and exact file
URL.

### Access constraints and gaps

- Ontario catalogue HTML intermittently returned HTTP 429 during research; the
  CKAN API and direct CSV remained accessible. Cache responses and use bounded
  retries.
- The roster has websites but no durable municipal ID, incorporation date, or full
  predecessor graph.
- Historical audited statements remain municipality-by-municipality.

## Quebec

### Roster, websites, hierarchy, and perimunicipal bodies

- Public directory: [Répertoire des municipalités](https://www.quebec.ca/gouvernement/portrait-quebec/repertoire-municipalites).
  The page expressly says the directory has no legal value, so preserve that
  qualification in source notes.
- Open-data package: [Répertoire des municipalités du Québec](https://www.donneesquebec.ca/recherche/fr/dataset/repertoire-des-municipalites-du-quebec).
- Current local-municipality CSV: [MUN.csv](https://donneesouvertes.affmunqc.net/repertoire/MUN.csv).
- Current MRC, metropolitan-community, and agglomeration CSV:
  [MRC_CM_Arg.csv](https://donneesouvertes.affmunqc.net/repertoire/MRC_CM_Arg.csv).
- Current borough CSV: [ARR.csv](https://donneesouvertes.affmunqc.net/repertoire/ARR.csv).
- Machine-readable organization relationships:
  [A01_CONVERT_XML_STRC.xml](https://donneesouvertes.affmunqc.net/repertoire/A01_CONVERT_XML_STRC.xml).
- Perimunicipal organizations and links:
  [A01_CONVERT_XML_ORG_PER_MUN.xml](https://donneesouvertes.affmunqc.net/repertoire/A01_CONVERT_XML_ORG_PER_MUN.xml)
  and [A01_CONVERT_XML_CORPO_ORG.xml](https://donneesouvertes.affmunqc.net/repertoire/A01_CONVERT_XML_CORPO_ORG.xml).

`MUN.csv` supplies the geographic code (`mcode`), name, designation code and text,
MRC/administrative associations, constitution date, population, contact details,
and website. Keep `mcode` as `qc.code-geographique`; do not put it into the semantic
canonical path. The relationship XML is preferable to reconstructing hierarchy
from display strings. Quebec's MRCs, metropolitan communities, agglomerations,
boroughs, intermunicipal boards, public transit bodies, and perimunicipal
organizations should be institutions when they have independent public identity or
reporting, not flattened into municipality attributes.

The files are refreshed in place. At release time download them once, record the
retrieval timestamp/hash, and build only from those frozen bytes.

### Geography and predecessors

- [Fichiers du code géographique du Québec](https://www.donneesquebec.ca/recherche/dataset/fichiers-code-geographique-quebec)
- Current complete D001 XML at research time:
  [d001_complet.xml](https://www.donneesquebec.ca/recherche/dataset/4479a1d9-9eb6-4080-9b4b-f4ab4e3170b4/resource/9fd0c852-1b7e-43ba-acfc-923bd6f4b867/download/d001_complet.xml)
- Historical D002 XML at research time:
  [d002.xml](https://www.donneesquebec.ca/recherche/dataset/4479a1d9-9eb6-4080-9b4b-f4ab4e3170b4/resource/34c64017-6043-4afc-a00c-49bcf3d3c162/download/d002.xml)
- Publisher's current description and archive:
  [Fichiers du code géographique du Québec – portrait et historique](https://statistique.quebec.ca/statistiques/divisions-territoriales/fichiers_code_geo/code-geographique-quebec.html)

D001 is the current municipal/geographic portrait. D002 records territorial
transactions since the code system began in 1964. Decode transaction types using
the package's metadata rather than treating every change as succession. Name,
designation, code, and partial-boundary changes can leave the institution
continuous; grouping/dissolution transactions can create real predecessor edges.

Quebec agglomerations are especially important: a central municipality and linked
municipalities share agglomeration powers, but the linked municipalities are not
owned by the central municipality. Represent the agglomeration as its own regional
institution and use sourced governance/membership relationships.

### Financial and annual reports

- Human/search interface: [Rapport financier](https://www.quebec.ca/gouvernement/gestion-municipale/finances-fiscalite-municipales/information-financiere/publications-financieres/rapport-financier)
- Open package: [Rapport financier des organismes municipaux et autres documents connexes](https://www.donneesquebec.ca/recherche/dataset/rapport-financier-des-organismes-municipaux-et-autres-documents)
- Derived comparison product: [Profil financier des municipalités locales](https://www.donneesquebec.ca/recherche/dataset/profil-financier-des-municipalites-locales)

The open package covers local municipalities, MRCs, metropolitan communities,
intermunicipal boards, and public transit organizations. Current resources include
actual-data CSV/XLSX, absent-organization lists, non-audited forecast data, and
codified form/field definitions. The files update daily and an organization can
retransmit a revision. Therefore a dated release must freeze the bytes and retrieval
time, and any later retransmission belongs in the next ontology release.

The search interface assembles an entity/year PDF, while open CSVs provide the
reported financial fields. Record these as provincial financial-report works. Do
not claim the assembled PDF is the municipality's original auditor-signed artifact
without checking its contents. A financial profile is a derived analytical product,
not an annual statement.

The province states that it does not publish this municipal financial information
for northern villages, Indian reserves, Indigenous settlements, Cree villages, the
Naskapi village, or Inuit reserved lands. Those governments require their own or a
federal/Indigenous-government source; absence from this package is not evidence
that the institution or its statements do not exist.

### Access constraints and gaps

- The directory resources are mutable in-place endpoints. Hash and retain every raw
  input used for a release.
- The open-finance package has hundreds of resources and a rolling maximum period;
  use the CKAN API rather than page scraping and archive resources before they roll
  off.
- Government sites are primarily French. Populate English only when upstream
  supplies English, per the product's bilingual rule.

## New Brunswick

### Current legal roster and structures

- Structure overview: [Local governance structure in New Brunswick](https://www2.gnb.ca/content/gnb/en/corporate/promo/local-governance/structure.html)
- Constituting regulation: [Local Governments Establishment Regulation 2022-50](https://laws.gnb.ca/en/document/cr/2022-50/20221012)
- Current convenient roster: [Local government and rural districts statistics 2025](https://www.gnb.ca/content/dam/GNB3/org/elg-egl/doc/2025-local-government-and-rural-districts-statistic.pdf)
- Maps/entity navigation: [Local governance maps](https://www2.gnb.ca/content/gnb/en/corporate/promo/local-governance/maps.html)

The current structure has 77 incorporated local governments and 12 rural districts.
Local-government legal forms include city, town, village, rural community, and
regional municipality. Rural districts came into effect on 2023-01-01; the
provincial minister administers their services and their elected councils are
advisory. Model each rural district as a local public institution with
`institution_type=government`, `government_level=other`, and
`legal_form=rural district` for the shallow release. A sourced `governed_by` edge
can point to the province/ministerial institution when that target is in scope.

The 2025 statistics PDF is a good bilingual enumeration and validation source, but
its row/entity display numbers must not be adopted as permanent IDs without a
published stability guarantee. The regulation schedules are the legal evidence for
names, types, and establishment/continuation.

Regional service commissions are independent regional institutions. Membership is
not ownership. They replaced 12 solid-waste commissions and 12 land-use planning
commissions in 2012, so those are predecessor candidates when historical scope is
expanded.

### Geography and the 2023 reform

- [GeoNB local governments](https://www.gnb.ca/en/campaign/geonb/data-catalogue/local-governments.html)
- [GeoNB rural districts](https://www.gnb.ca/en/campaign/geonb/data-catalogue/rural-districts.html)
- [GeoNB data catalogue](https://www.gnb.ca/en/campaign/geonb/data-catalogue.html)
- Reform context: [About local governance reform](https://www2.gnb.ca/content/gnb/en/corporate/promo/local-governance/about.html)

GeoNB describes the local-government polygons as the graphical representation of
boundaries in Regulation 2022-50, effective 2023-01-01, with ad-hoc updates. It
offers file geodatabase, shapefile, and KML in EPSG:2953 under the Open Government
Licence. The rural-district layer is separate. Archive a concrete downloaded file,
not merely the catalogue page.

The reform replaced 104 local governments and 236 local service districts with the
current 77 local governments and 12 rural districts. A new entity may combine whole
or partial predecessor areas; do not emit a single predecessor based on name
similarity. Use Regulation 2022-50 schedules and historical GeoNB municipal/local
service district layers to generate effective 2023-01-01 succession and territorial
evidence. A partial transfer can be recorded in source notes or a future territorial
event table; it is not automatically corporate succession.

### Financial and annual reports

- Provincial publication index: [Publications and reports of Environment and Local Government](https://www.gnb.ca/en/org/environment-local-government/elg-publications.html)
- Legal requirement: [Annual Report Regulation 2018-54](https://laws.gnb.ca/en/document/cr/2018-54)

The publication index provides annual `Local government and rural districts
statistics` reports from 2019 onward. Those reports contain budget, tax, borrowing,
and structural information; they are not the individual audited statements.

Regulation 2018-54 requires each local government to prepare its preceding-year
annual report by June 30 and requires the report to contain its audited financial
statements. It also requires reporting about municipal corporations and how to
access their statements/annual reports. This makes local-government annual reports
a useful discovery source for otherwise-missed controlled or partly held
corporations. No centralized provincial bulk archive of those local annual reports
was found, so scrape each official local-government website and retain the annual
report as a container asset when statements are embedded.

### Access constraints and gaps

- The current statistics PDF provides no guaranteed durable local-government ID.
- Province-hosted maps/contact pages are useful discovery aids, but websites and
  historic audited documents still require per-entity crawling.
- The 2023 many-to-many reform cannot be represented accurately by fuzzy name
  reconciliation alone.

## Prince Edward Island

### Roster, websites, and legal forms

- Current official roster: [PEI Municipalities](https://www.princeedwardisland.ca/en/information/housing-land-and-communities/pei-municipalities)
- Contacts and website discovery: [Municipal Directory](https://www.princeedwardisland.ca/en/feature/municipal-directory)

The roster, published 2025-01-28, lists 2 cities, 10 towns, and 45 rural
municipalities (57 total). “Resort” appears within the 45-item rural-municipality
section. Preserve the source designation exactly; if legal research needs to
distinguish the Resort Municipality class, set `legal_form` from the Municipal
Government Act/continuation order rather than overwriting the roster count.

The directory provides contact, governance, population, service/bylaw, and website
information through an interactive form. Treat the government's listed website as
the official website when present. The form is not a documented bulk API, so a
scraper should save the submitted result or use a browser-capable fallback and
should not assume a stable HTML layout.

Under the current framework, former “community” municipalities were continued as
rural municipalities. A status conversion without a new corporation should not
create a new canonical ID. Amalgamations such as current multi-community
municipalities require the relevant orders to decide whether a successor was
created.

### Geography and predecessors

- ArcGIS service directory: [municipal_zones FeatureServer layer 0](https://gis.princeedwardisland.ca/server/rest/services/municipal_zones/FeatureServer/0)
- Departmental annual report snapshot: [Housing, Land and Communities Annual Report 2024-2025](https://www.princeedwardisland.ca/sites/default/files/5fd0/HLCAnnualReport2024_25.pdf)

The ArcGIS layer supports machine-readable queries including JSON/GeoJSON and has
municipal-name and source fields. `OBJECTID` is an ArcGIS row identifier, not an
institution ID. Do not adopt `FCODE`, `SOURCEID`, or `USERNUM` until the service's
metadata/data owner documents their semantics and stability. The layer reports that
it is not versioned, so archive each release extract with its service metadata.

The 2024-2025 annual report confirms 57 municipalities as of 2025-03-31 and records
restructuring activity at an aggregate level. Use Municipal Government Act orders,
Gazette notices, and dated prior rosters for exact dissolution/amalgamation edges.

### Financial and annual reports

- Central search: [Municipal Financial Document Search](https://www.princeedwardisland.ca/en/feature/municipal-financial-document-search)
- Governance/filing guidance: [Local Governance Handbook, second edition](https://www.princeedwardisland.ca/sites/default/files/publications/local_governance_handbook_2nd_edition_final_oct_19_2022_final.pdf)

The search explicitly offers recent municipal financial statements by municipality
and fiscal year ending March 31. The handbook describes submission and public-notice
deadlines and says the province publishes submitted statements. This is the best
central statement source in this region after Quebec, but the search uses an
interactive form and does not expose a documented bulk endpoint on its landing
page. Enumerate all roster/year combinations with bounded concurrency, preserve the
result/landing page and exact PDF URL, and fall back to Municipal Affairs or the
municipal site when a result is absent.

### Access constraints and gaps

- Both the directory and financial search are form-driven; missing results can mean
  no document, a temporary service failure, or a form/scraper problem. Record the
  distinction in crawl audit data.
- The current roster does not expose a durable machine ID.
- The ArcGIS layer has no historical moments and its numeric fields are not yet
  documented as institution identifiers.

## Newfoundland and Labrador

### Current roster and legal distinctions

- Directory landing page: [Municipal Directory](https://www.gov.nl.ca/mca/municipal-directory/)
- Towns, Inuit Community Governments, and cities PDF (2026-03-16):
  [directory PDF](https://www.gov.nl.ca/mca/files/Newfoundland-and-Labrador-Directory-of-Towns-ICGs-and-Cities-as-of-March-16-2026.pdf)
- Local service districts PDF (2026-03-16):
  [LSD directory PDF](https://www.gov.nl.ca/mca/files/Newfoundland-and-Labrador-Directory-of-Local-Service-Districts-Information-as-of-March-16-2026.pdf)
- Legislation index: [Municipal and Community Affairs legislation](https://www.gov.nl.ca/mca/department/legislation/)

The department warns that directory accuracy depends on communities notifying its
regional offices. The PDFs contain name, region, head of council/AngajukKak, clerk,
phone, email, address, and office hours, but do not provide a reliable website for
every entity.

Do not flatten the combined PDF into one type:

- cities are municipal governments under city-specific legislation;
- towns are incorporated municipalities under the Towns and Local Service Districts
  Act;
- Inuit Community Governments are Inuit governments;
- local service districts are separate unincorporated service/governance bodies.

The Towns and Local Service Districts Act took effect on 2025-01-01 and replaced the
Municipalities Act, 1999 for its scope. Preserve the legal basis and effective date;
do not assume the statutory replacement created successor corporations for every
existing town.

### Geography and predecessors

- Current legal-boundary landing: [Municipal Boundaries](https://www.gov.nl.ca/mca/municipal-boundaries/)
- Legacy open dataset: [Municipalities and local service districts](https://opendata.gov.nl.ca/public/opendata/page/?id=265&page-id=datasetdetails)
- Provincial ArcGIS land-use service: [GeoAtlas Land Use MapServer](https://dnrmaps.gov.nl.ca/arcgis/rest/services/GeoAtlas/Land_Use/MapServer)

The current boundary page links incorporated-municipality boundaries established
under the Towns and Local Service Districts Act and distributes KMZ. It separately
warns that municipal planning-area boundaries are a different legal geography.
Never substitute a planning boundary for the incorporated boundary.

The open-data municipality/LSD shapefile was last modified in 2014 and is stale for
a 2026 release. It is useful as a historical snapshot only. The ArcGIS service can
be queried as a discovery layer, but its layer metadata/update history should be
captured and reconciled to the current directory and legal-boundary page before it
is called current.

Many LSDs and Indigenous/Inuit entities will not match a StatsCan CSD one-to-one.
Permit zero, one, or many evidenced `governs`/`serves` associations rather than
forcing a name match.

### Financial and annual reports

- Finance program: [Municipal Finance](https://www.gov.nl.ca/mca/municipal-finance/)
- Municipal operating grants: [Municipal Operating Grants](https://www.gov.nl.ca/mca/for/mog/)
- Current disclosure guidance confirming Towns and Local Service Districts Act s.
  92 publication: [ATIPPA Guide for Towns](https://www.gov.nl.ca/atipp/files/info-pdf-atippa-guide-for-municipalities.pdf)

The department receives/reviews municipal financial information, and grant
eligibility requires signed audited PSAB-compliant statements, but no central public
archive of individual municipal statements was identified. Section 92 guidance says
town councils must publish financial statements and the auditor's report. Scrape
each official town/city/ICG site and clearly distinguish a budget, provincial grant
form, or financial evaluation from an audited financial statement.

### Access constraints and gaps

- The roster is PDF-only and self-reported; exact municipality websites require
  separate discovery and verification.
- The legacy provincial open-data geometry is more than a decade old.
- City legislation and Inuit-government law differ from the statute governing
  towns/LSDs.
- Historical audited statements are decentralized and will need per-site crawling,
  web archives, or direct municipal requests.

## Proposed adapter output and validation

Each provincial adapter should emit frozen raw-source metadata plus normalized rows
under this minimal contract:

```text
institutions: canonical_id, names, website_url, institution_type,
              government_level, legal_form, status, active dates, source_id
identifiers:  canonical_id, scheme, value, preferred, source_id
relationships: source canonical_id, target canonical_id, type,
               valid dates, source_id, notes
geography links: canonical_id, StatsCan/provincial geography ID, role,
                 source_id, match method/confidence notes
documents: institution canonical_id, type, fiscal dates, landing URL,
           exact asset URL, source_id, retrieval/hash metadata
```

Release validation should fail or warn on:

- a current roster row without a canonical institution;
- duplicate use of a provincial or StatsCan identifier in one release;
- tier or parent inferred only from an institution's English/French name;
- a rural/service district represented as an incorporated municipality;
- a post-2021 institution assigned a 2021 CSD solely by name similarity;
- a financial return, budget, profile, or blank form labelled as audited statements;
- a predecessor edge derived from a partial annexation without corporate evidence;
- a direct-download source whose bytes/hash were not frozen;
- a website inferred from an unaffiliated directory when an official roster supplies
  one; and
- an English translation invented where the upstream source is French-only.

## Recommended implementation order

1. Quebec first: it has durable geographic codes, hierarchy/perimunicipal XML,
   websites, machine-readable history, and centralized financial data.
2. Ontario second: the current roster/websites and FIR are straightforward, but
   audited PDFs remain decentralized and municipal IDs need careful reconciliation.
3. New Brunswick third: ingest the legal 2023 roster and boundaries, then build the
   many-to-many reform crosswalk before claiming predecessor completeness.
4. PEI fourth: enumerate the central financial search and directory with a
   browser/form-capable scraper.
5. Newfoundland and Labrador fifth: separate the four legal institution classes and
   treat statement discovery as decentralized.
