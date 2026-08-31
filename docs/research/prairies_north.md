# Prairie and northern local-government source inventory

Status: research handoff
Checked: 2026-08-21
Scope: Saskatchewan, Manitoba, Yukon, Northwest Territories, and Nunavut

This note identifies authoritative sources and normalization rules for a future
`Warehouse::InstitutionRelease` source adapter. It deliberately does not add records to a
release. The upstream sources differ enough that an adapter should retain provenance and emit
reviewable geography matches rather than flattening every list into "municipalities."

## Recommended source-record contract

The source adapter should emit one record for each legal or recognized government institution,
then emit identifiers, names, geography associations, and relationships separately.

```text
SourceInstitution
  source_key                 stable identifier in the upstream source, when available
  jurisdiction_code         ca-sk | ca-mb | ca-yt | ca-nt | ca-nu
  official_name
  legal_form                 controlled vocabulary described below
  institution_kind          municipal_government | community_government |
                            indigenous_government | advisory_body |
                            territorial_administrative_area
  website_url                official institution website, not a directory profile
  source_url                 page or file from which the record was read
  source_updated_on          upstream date, if stated
  retrieved_at
  incorporation_date         if supplied by the legal roster
  status                     active | inactive | historical | uncertain
  service_region             source metadata, not necessarily a parent
  notes

SourceIdentifier
  source_key
  scheme                     statcan_csd_uid | isc_band_number | source_directory_id | ...
  value
  source_url

SourceRelationship
  subject_source_key
  predicate                  within | administered_by | advises | provides_services_for |
                            successor_of | overlaps
  object_source_key
  valid_from / valid_to
  source_url

SourceDocument
  source_key
  document_kind              audited_financial_statements | annual_report |
                            budget | source_listing
  fiscal_period_start / fiscal_period_end
  publication_date
  document_url
  source_page_url
  language                   en | fr | iu | ikt | und
  checksum
```

`source_key` is not the ontology's canonical ID. The release builder should mint the canonical
semantic ID after deduplication and preserve all source identifiers as aliases.

## Statistics Canada geography mapping

Use the Statistics Canada 2025 intercensal products for the current release boundary date and
retain the 2021 SGC classification for type definitions and historical crosswalks:

- [2025 Census Subdivision Boundary File and Interim List](https://www12.statcan.gc.ca/census-recensement/geo/intercens-eng.cfm)
- [Interim List of Changes to Municipal Boundaries, Status and Names](https://www12.statcan.gc.ca/census-recensement/2021/geo/ref/interim-interimaire/index-eng.cfm)
- [Standard Geographical Classification 2021](https://www.statcan.gc.ca/en/subjects/standard/sgc/2021/index)
- [Census subdivision types](https://www12.statcan.gc.ca/census-recensement/2021/ref/dict/tab/index-eng.cfm?ID=t1_5)
- [CSDUID structure](https://www150.statcan.gc.ca/n1/pub/92-151-g/2021001/tbl/tbl4_1-eng.htm)
- [Designated-place types](https://www12.statcan.gc.ca/census-recensement/2021/ref/dict/tab/index-eng.cfm?ID=t1_6)
- [2025 interim changes table](https://www150.statcan.gc.ca/n1/pub/92f0009x/2024001/tbl/tbl01-eng.htm)

The seven-character `CSDUID` is a geography identifier: two province/territory digits, two
census-division digits, and three census-subdivision digits. It is not an organization ID.
Statistics Canada CSDs include municipalities **and statistical equivalents**, including Indian
reserves, Indian settlements, unorganized territories, and other areas. Designated places are
also statistical geographies and do not imply a corporation or council.

Recommended matching procedure:

1. Build the institution roster from the jurisdiction's legal or administrative directory.
2. Generate candidates by province/territory, current official name, historical name, and the
   compatible Statistics Canada CSD type.
3. Review all non-exact candidates and all name-change cases against the interim change list.
4. Store confirmed CSDs as `physical_jurisdiction` associations, never as the canonical ID.
5. Permit zero, one, or many CSD associations per institution. Do not manufacture a match.
6. Store reserve, settlement-land, traditional-territory, and municipal-boundary associations
   independently. Spatial overlap is not ownership or administrative subordination.

Examples that require manual review include a rural municipality surrounding an urban
municipality, a First Nation government associated with several reserves, a designated authority
delivering local services, and an unincorporated community represented by an advisory council.

## Saskatchewan

### Roster and websites

Primary roster: the Government of Saskatchewan [Municipal Directory](https://www.saskatchewan.ca/government/municipal-administration/municipal-directory).
It is browsable by city, town, village, resort village, rural municipality, northern town,
northern village, northern hamlet, and Northern Saskatchewan Administration District. Directory
profiles are the preferred source for official name, classification, contact information, and
official website URL.

The province's [municipal-system overview](https://www.saskatchewan.ca/government/government-structure/local-federal-and-other-governments/your-local-government/about-the-saskatchewan-municipal-system)
reports 761 urban, rural, and northern municipalities and explains the governing legislation.
Use the directory, not the count, to materialize a dated roster.

Suggested legal forms:

| Upstream classification | `legal_form` | Treatment |
| --- | --- | --- |
| City | `city` | Municipal corporation under *The Cities Act* |
| Town | `town` | Urban municipal corporation |
| Village | `village` | Urban municipal corporation |
| Resort Village | `resort_village` | Urban municipal corporation |
| Rural Municipality | `rural_municipality` | Municipal corporation |
| Northern Town | `northern_town` | Northern municipal corporation |
| Northern Village | `northern_village` | Northern municipal corporation |
| Northern Hamlet | `northern_hamlet` | Northern municipal corporation |
| Northern Saskatchewan Administration District | `territorial_administrative_area` | Administrative area, not a municipal corporation |

Do not assume that every northern settlement is a northern municipality. Provincially
administered settlements and the Northern Saskatchewan Administration District require distinct
records only when an authoritative source identifies an institution or administrative body.

### Relationships

- Link each municipal corporation `within` Saskatchewan.
- Urban municipalities geographically enclosed by rural municipalities remain peer municipal
  corporations; do not model the rural municipality as their owner or institutional parent.
- A regional authority, board, police service, or joint body needs its own constituting source.
- Northern administrative regions are service metadata unless legislation establishes a parent.

### Financial statements and annual reports

The Government of Saskatchewan launched a central municipal statement collection in January
2026. The [announcement](https://www.saskatchewan.ca/government/news-and-media/2026/january/15/municipal-financial-statements-now-available-on-saskatchewanca)
states that three years of audited statements, initially 2022 through 2024, are available for
every municipality. Use the Publications Saskatchewan
[Municipal Financial Statements category](https://publications.saskatchewan.ca/#/categories/6585)
as the primary document listing. Capture municipality, fiscal year, direct document URL, listing
URL, publication metadata, and checksum.

The province's [municipal financial guidance](https://www.saskatchewan.ca/Government/Municipal-Administration/Funding-Finances-and-Asset-Management/Financial)
and [access-to-information guidance](https://www.saskatchewan.ca/Government/Municipal-Administration/Tools-Guides-and-Resources/access-to-municipal-information)
confirm the annual audited-statement and public-access duties.

No equivalent central collection of municipal annual reports was identified. Discover annual
reports on the directory-provided municipal website, then in council-agenda/document portals. Do
not relabel a budget, financial statement, or provincial municipal-data summary as an annual
report.

### Indigenous-government boundary

Keep First Nations and Métis governments out of the municipal namespace. The province's
[First Nations, Métis and northern affairs directory](https://www.saskatchewan.ca/residents/first-nations-citizens/saskatchewan-first-nations-metis-and-northern-affairs-directory)
is a discovery source; the federal First Nation Profiles source below supplies recognized First
Nation identifiers. A reserve CSD is a physical jurisdiction and is not the First Nation
government itself.

## Manitoba

### Roster and websites

Primary roster: Manitoba's [Municipal Officials Directory](https://www.gov.mb.ca/mr/municipal-officials-directory.html),
including its live directory application and [PDF export](https://www.gov.mb.ca/mr/contactus/pubs/mod.pdf).
The PDF was marked updated November 13, 2025 when checked and includes municipal contacts and
website URLs. Manitoba's [Municipal Finance and Advisory Services page](https://www.gov.mb.ca/mr/mfpp/index.html)
states that the province supports all 137 municipalities.

The [Municipal Act](https://web2.gov.mb.ca/laws/statutes/ccsm/m225.php?lang=en) organizes
municipalities principally as urban and rural municipalities. A municipality may retain a legacy
style such as city, town, village, or rural municipality in its official name. Preserve both the
legal class and the official style. Winnipeg is governed separately under the *City of Winnipeg
Charter*.

Suggested legal forms:

| Upstream classification | `legal_form` | Treatment |
| --- | --- | --- |
| Urban municipality | `urban_municipality` | Corporation under *The Municipal Act* |
| Rural municipality | `rural_municipality` | Corporation under *The Municipal Act* |
| City of Winnipeg | `charter_city` | Separate charter |
| Local government district | `local_government_district` | Only when current directory/legislation confirms it |
| Local urban district | `local_urban_district` | Submunicipal committee/area, not a municipality |
| Northern incorporated community | `northern_incorporated_community` | Corporation under northern-community legislation |
| Northern unincorporated community | `northern_unincorporated_community` | Community government/body, not a municipal corporation |

Use the current [Local Government Districts Regulation](https://web2.gov.mb.ca/laws/regs/current/040-97.php?lang=en)
and the current officials directory to confirm surviving LGDs. Never infer active status from an
old regulation or historical name.

### Northern communities and hierarchy

The [Northern Affairs Act](https://web2.gov.mb.ca/laws/statutes/ccsm/n100.php?lang=en) distinguishes
incorporated and unincorporated northern communities and excludes Indian reserves. The province's
[community profiles](https://www.gov.mb.ca/inr/publications/community_profiles.html) are the roster
and discovery source for Northern Affairs communities. The page explicitly labels some
incorporated communities, but the adapter should check the Act's current regulations or an
incorporation order before assigning corporate status.

- A local urban district is a child/advisory institution of its parent rural municipality; it is
  not a peer municipality.
- A northern unincorporated community may have a council and delegated functions without being a
  corporation.
- A First Nation and a same-named northern community are separate entities.
- "Central," "Interlake," or another provincial service region is not an organizational parent.

### Financial statements and annual reports

No public central library of municipality-level audited statements was identified. Manitoba
requires audited statements and delivery to the minister, while public access is generally
provided through notice and inspection. The province's
[2026 Municipal Finance and Advisory Services bulletins](https://www.gov.mb.ca/mr/mfas/bulletins_2026.html)
include the June 30, 2026 deadline for 2025 audited statements. Its
[PSAB page](https://www.gov.mb.ca/mr/mfas/mfas_psab.html) provides templates and guidance, not the
municipalities' statements.

For both audited statements and annual reports, crawl the official website from the Municipal
Officials Directory. Search finance/transparency pages first, then council agenda packages. Store
an HTML availability notice as `source_listing`, not as the statement itself. Historical
provincial statistical compilations derived from municipal filings are secondary datasets, not
substitutes for source financial statements.

### Indigenous-government boundary

Use the federal First Nation Profiles roster for Indian Act First Nations. Manitoba's
[Indigenous Governing Bodies directory](https://www.gov.mb.ca/fs/ijto/print%2Cigb-directory.html)
is useful supplemental evidence in its statutory child-and-family-services context, but is not a
complete general-purpose roster of Indigenous governments. Do not merge a reserve CSD, northern
community, and First Nation government because they share a name.

## Yukon

### Roster and websites

The Government of Yukon [municipal and local advisory council elections page](https://yukon.ca/en/municipal-and-local-advisory-council-elections)
is a concise current roster. It lists eight municipalities—Carmacks, Dawson, Faro, Haines
Junction, Mayo, Teslin, Watson Lake, and Whitehorse—and five local advisory councils—Ibex Valley,
Marsh Lake, Mount Lorne, Tagish, and Carcross/South Klondike.

Use the [Local Government Directory](https://yukon.ca/en/your-government/government-government-relations/view-local-government-directory)
and its [2025 PDF](https://yukon.ca/sites/default/files/2025-01/2025-01-21%20-%20Local_Government_Directory.pdf)
for official names, contacts, and website URLs. It identifies Whitehorse and Dawson as cities,
Faro and Watson Lake as towns, and Carmacks, Haines Junction, Mayo, and Teslin as villages. The
[Municipal Act](https://laws.yukon.ca/cms/images/LEGISLATION/PRINCIPAL/2002/2002-0154/2002-0154_4.pdf)
is the enabling statute.

### Local advisory councils and hierarchy

The Yukon Open Data [Local Advisory Areas dataset](https://open.yukon.ca/data/local-advisory-areas)
explains that unincorporated areas may have advisory or hamlet councils. Model a local advisory
council as an `advisory_body`, with an `advises` relationship to its local advisory area and an
administrative `within` relationship to the territorial government. It is not a municipality and
does not own the community. The [local area plans page](https://yukon.ca/en/housing-and-property/land-and-property/find-local-area-plan)
also distinguishes unincorporated communities from municipalities.

### Financial statements and annual reports

The [municipal filing deadlines page](https://yukon.ca/en/your-government/government-government-relations/find-out-deadlines-municipal-filings)
states that audited financial statements and the auditor's report are due to the director by June
30 and that public notice of availability for inspection is required. No central public
municipality-level statement or annual-report repository was identified. Use the Local Government
Directory's website URL and municipal council document portals. Yukon
[Public Accounts](https://yukon.ca/en/public-accounts) are territorial statements and must not be
attached to municipalities.

### First Nations and overlap

The Government of Yukon [First Nations overview](https://yukon.ca/en/your-government/about-yukon/find-out-about-yukon-first-nations)
lists 14 Yukon First Nations. The
[agreements directory](https://yukon.ca/en/en/your-government/government-government-relations/agreements-indigenous-governments-groups?wbdisable=false)
states that 11 have final and self-government agreements and also lists transboundary groups.
Use agreement and First Nation sources to represent those governments, not a municipal adapter.

A First Nation government, municipality, traditional territory, settlement land, and CSD may
overlap. None of those spatial facts establishes ownership. A Statistics Canada Indian
settlement CSD is not automatically an institutional record.

## Northwest Territories

### Roster and websites

Primary roster: Municipal and Community Affairs' [Communities list](https://www.maca.gov.nt.ca/en/communitylist),
which reports 33 communities. Use the [Community Government Mail Merge](https://www.maca.gov.nt.ca/en/mail-merge?order=field_official_community_name&sort=asc)
or its spreadsheet download as the machine-readable roster seed and the
[Community Contacts Listing](https://www.maca.gov.nt.ca/en/community-contact-listing) for current
contacts. Then follow each official community profile—such as
[Aklavik](https://www.maca.gov.nt.ca/en/content/aklavik)—to obtain official community-government
name, status, incorporation date, region, officials, and official website URL.

The MACA [authority overview](https://www.maca.gov.nt.ca/en/services/municipal-elections/where-your-authority-comes)
identifies the Cities, Towns and Villages Act, Hamlets Act, Charter Communities Act, Tłı̨chǫ
Community Government Act, Indian Act, and relevant self-government arrangements. Check current
consolidations in the [NWT legislation index](https://www.justice.gov.nt.ca/en/legislation/).

Suggested legal forms include `city`, `town`, `village`, `hamlet`, `charter_community`,
`tlicho_community_government`, `designated_authority`, and
`self_government_community_government`. Populate the exact form from the profile, not from a count
or from the plain-language label "community."

### Designated authorities and hierarchy

MACA's [community land-use planning overview](https://www.maca.gov.nt.ca/en/services/community-land-use-planning-and-development)
distinguishes municipalities incorporated under territorial enabling legislation from
designated-authority communities where a First Nation band council delivers municipal-type
services through MACA funding.

- When the recognized band council itself is the service-delivery authority, prefer one
  institution with multiple classifications and identifiers, plus
  `provides_services_for(community geography)`. Create two entities only if the source identifies
  two separate legal bodies.
- Délı̨nę Got'ı̨nę Government is a self-government/community-government hybrid and requires its
  agreement/legislation, not a generic hamlet classification.
- Tłı̨chǫ community governments have their own statutory form. Do not make them subsidiaries of
  the Tłı̨chǫ Government without an explicit legal relationship source.
- MACA's five regions are departmental service regions, not institutional parents or owners.

Use the territorial [Indigenous government directory](https://www.eia.gov.nt.ca/en/nwt-indigenous-government-directory)
and [Indigenous governments overview](https://www.eia.gov.nt.ca/en/priorities/indigenous-governments-nwt)
as a separate roster for regional and community-based Indigenous governments.

### Financial statements and annual reports

MACA's [financial-management guidance](https://www.maca.gov.nt.ca/en/services/municipal-elections/your-role-financial-management)
states that annual financial statements are independently audited and submitted to the minister
within 120 days of fiscal year-end. MACA publishes a
[sample statement format](https://www.maca.gov.nt.ca/sites/maca/files/resources/financial_statements_format.pdf),
not a central collection of actual community statements.

No public central municipality/community-government audited-statement or annual-report library
was identified. Discover documents from each MACA profile's official website, then council
agendas and public-notice pages. Do not store the sample format, a MACA funding update, or the
GNWT Public Accounts as a community government's financial statement.

## Nunavut

### Roster and websites

Nunavut has 25 municipal corporations: Iqaluit is a city under the *Cities, Towns and Villages
Act* and the other 24 are hamlets under the *Hamlets Act*. Current official legal sources are the
Nunavut Legislation consolidations for the
[Hamlets Act](https://www.nunavutlegislation.ca/en/consolidated-law/hamlets-act-consolidation)
and [Cities, Towns and Villages Act](https://www.nunavutlegislation.ca/en/consolidated-law/cities-towns-and-villages-act-consolidation).
The [Government of Nunavut 2026–2030 Business Plan](https://www.gov.nu.ca/sites/default/files/documents/2026-05/2026-2030_Business_Plans_-_ENG.pdf)
also confirms that Iqaluit is the only city and describes hamlet funding constraints.

No single current Government of Nunavut web directory with all official website URLs was
identified. Seed the 25-name roster from the statutes' continuation/name-change orders and check
it against the Government of Nunavut's
[community/hamlet office directory](https://www.gov.nu.ca/sites/default/files/documents/2023-12/ELCC%20Licensed%20Daycare%20Handbook%20-%20EN.pdf),
which lists all municipal offices and phone numbers. Use each corporation's own site as the
authoritative `website_url`; use [211 Nunavut's municipal-office listing](https://nu.211.ca/results/?topicPath=72)
only as a discovery source and verify every link on the destination site. The Nunavut Association
of Municipalities is an association, not a government roster authority.

Names need effective-dated aliases. Examples in current sources include Kinngait (formerly Cape
Dorset), Sanirajak (formerly Hall Beach), Naujaat (formerly Repulse Bay), and the distinction
between the Hamlet of Resolute and the community label Resolute Bay. Legal continuation and
name-change orders should control canonical names for the release date.

### Relationships and Inuit organizations

- Link every municipal corporation `within` Nunavut; the Qikiqtaaluk, Kivalliq, and Kitikmeot
  regions are geographic/administrative metadata, not parents or owners.
- A hamlet corporation and its municipal boundary are separate organization and geography
  records.
- Nunavut Tunngavik Incorporated and the regional Inuit associations are Nunavut Agreement
  organizations. They are neither municipalities nor departments of the Government of Nunavut.
  Model their agreement-defined roles from their constituting sources.
- Inuit organizations, hunters and trappers organizations, district education authorities, and
  housing associations are distinct public-interest bodies and must not be folded into the
  municipal corporation because they operate in the same community.

### Financial statements and annual reports

The *Hamlets Act* and *Cities, Towns and Villages Act* contain budgeting, audit, and financial
administration requirements. Government contribution policies also define a municipal
corporation as one established or continued under those Acts. No central public collection of
actual municipality-level audited statements or annual reports was identified.

Use the verified official municipal website first, then council agenda packages and public
notices. Retain the Government of Nunavut source page when a document is hosted on `gov.nu.ca`,
but make the municipality the document subject only when the PDF itself is the municipality's
statement. Government of Nunavut Public Accounts, departmental business plans, contribution
policies, and municipal training templates are not municipal financial statements.

## First Nation Profiles and financial statements

For Indian Act First Nations in Saskatchewan and Manitoba, and for First Nation/band-government
records that remain in scope in the territories, use Indigenous Services Canada's
[First Nation Profiles](https://services.sac-isc.gc.ca/fnp/main/Index.aspx?lang=eng). It exposes
First Nation, tribal council, reserve/settlement/village, political organization, geographic, and
governance views. Preserve the ISC band number as an external identifier; do not turn a reserve
number or reserve CSD into the government's canonical ID.

The profile system warns that northern-community information may be unavailable or inconsistent
because northern and First Nation communities are administered in different source systems. In
Yukon, NWT, and Nunavut, prefer the applicable self-government agreement and territorial roster
where they conflict with a generic profile.

For available audited consolidated statements, use the profile system's
[First Nations Financial Transparency Act search](https://fnp-ppn.aadnc-aandc.gc.ca/fnp/main/Search/SearchFF.aspx?lang=eng).
Record the band number, fiscal period, document label, direct binary URL, search/profile page,
language, and checksum. A missing year is missing data, not evidence that the First Nation did not
prepare statements. The FNFTA collection covers First Nations to which the relevant disclosure
rules apply; it is not a financial-statement source for Inuit organizations, Métis governments,
self-governing Yukon First Nations, territorial municipal corporations, or all northern
community governments.

## Adapter and release quality checks

Before a dated release is accepted:

1. Reconcile the emitted count against the dated official roster, by legal form.
2. Require `source_url` and `retrieved_at` on every institution and relationship assertion.
3. Require a verified official `website_url` or an explicit `nil` with a discovery note; do not
   use a directory profile URL as though it were the institution's website.
4. Reject duplicate current canonical names within the same namespace unless the legal forms or
   governing sources prove distinct institutions.
5. Preserve historical names and predecessor/successor relationships with effective dates.
6. Review every StatsCan association that is not an exact compatible name/type match.
7. Reject organizational parent/ownership edges inferred only from geographic containment,
   funding, service regions, or shared names.
8. Verify that each document names the institution and fiscal period on the document itself.
9. Store both the direct document URL and the source listing/page. Checksum downloaded files so a
   static release remains reproducible if an upstream URL changes.
10. Preserve upstream language exactly. Add translated labels only when the upstream source is
    bilingual or multilingual; do not machine-invent an "official" French, Inuktut, or
    Indigenous-language name.

## Known source gaps

- Manitoba, Yukon, NWT, and Nunavut do not appear to expose centralized public collections of
  municipality-level audited statements comparable to Saskatchewan's 2026 collection.
- Municipal annual reports are generally decentralized in all five jurisdictions.
- Nunavut lacks an obvious current, authoritative all-municipality website directory; official
  URLs require destination verification.
- Northern source systems use "community government," "municipality," "designated authority,"
  "band council," and "self-government" in partially overlapping ways. Legal form must come from
  the profile, statute, order, or agreement rather than the page's generic prose.
- Statistics Canada geography changes can lag a legal change or use a statistical equivalent.
  Store match confidence and review evidence rather than forcing equality.
