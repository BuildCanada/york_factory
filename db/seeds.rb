# Seed data sources for York Factory pipeline

Warehouse::Source.find_or_create_by!(name: "infobase_authorities") do |s|
  s.url = "https://open.canada.ca/data/dataset/a35cf382-690c-4221-a971-cf0fd189a46f/resource/3bafde71-8cb8-460e-93e2-691295221063/download/eav_eac_en.csv"
  s.format = "csv"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "estimates_main_2025_26") do |s|
  s.url = "https://www.canada.ca/content/dam/tbs-sct/documents/planned-government-spending/main-estimates/2025-26/organization-summary.csv"
  s.format = "csv"
  s.fetch_frequency = "manual"
end

# Geo boundary sources — StatsCan 2021 Census
Warehouse::Source.find_or_create_by!(name: "statcan_boundary_da") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lda_000a21a_e.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_boundary_ct") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lct_000a21a_e.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_boundary_csd") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lcsd000a21a_e.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_boundary_fsa") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lfsa000a21a_e.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "elections_canada_fed") do |s|
  s.url = "https://ftp.maps.canada.ca/pub/elections_elections/Electoral-districts_Circonscription-electorale/federal_electoral_districts_boundaries_2023/FED_CA_2023_EN-SHP.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_boundary_pr") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lpr_000a21a_e.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_boundary_cd") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lcd_000a21a_e.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_boundary_er") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/ler_000a21a_e.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_boundary_cma") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lcma000a21a_e.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_boundary_popctr") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lpc_000a21a_e.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_geo_relationship") do |s|
  s.url = "https://www12.statcan.gc.ca/census-recensement/2021/geo/aip-pia/attribute-attribs/index2021-eng.cfm?year=2021"
  s.format = "csv"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "statcan_da_population") do |s|
  s.url = "https://www150.statcan.gc.ca/n1/tbl/csv/98100001-eng.zip"
  s.format = "csv"
  s.fetch_frequency = "manual"
end

# Provincial electoral districts
Warehouse::Source.find_or_create_by!(name: "ped_ontario") do |s|
  s.url = "https://www.elections.on.ca/content/dam/NGW/sitecontent/2017/preo/shapefiles/Electoral%20District%20Shapefile%20-%202022%20General%20Election.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "ped_alberta") do |s|
  s.url = "https://www.elections.ab.ca/uploads/2019Boundaries_ED-Shapefiles.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "ped_bc") do |s|
  s.url = "https://openmaps.gov.bc.ca/geo/pub/wfs?service=WFS&version=1.0.0&request=GetFeature&typeName=pub:WHSE_ADMIN_BOUNDARIES.EBC_ELECTORAL_DISTS_BS11_SVW&outputFormat=SHAPE-ZIP"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "ped_quebec") do |s|
  s.url = "https://donnees.electionsquebec.qc.ca/autres/provincial/circonscriptions_electorales_2022_shapefile.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "ped_manitoba") do |s|
  s.url = "https://www.electionsmanitoba.ca/downloads/2018_Final_ED_Manitoba_Public_Urban.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "ped_manitoba_wpg") do |s|
  s.url = "https://www.electionsmanitoba.ca/downloads/2018_Final_ED_Winnipeg_Public_Urban.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "ped_saskatchewan") do |s|
  s.url = "https://cdn.elections.sk.ca/scbcmaps/2022-SaskBoundaries-Final-Recommended-ShapeFiles.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "ped_new_brunswick") do |s|
  s.url = "https://gnb.socrata.com/api/geospatial/c468-yuuy?method=export&format=Shapefile"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "ped_yukon") do |s|
  s.url = "https://map-data.service.yukon.ca/GeoYukon/Administrative_Boundaries/Yukon_Electoral_Districts/Yukon_Electoral_Districts.shp.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "ped_nwt") do |s|
  s.url = "https://www.geomatics.gov.nt.ca/en/electoral-district-boundaries"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

# Municipal wards
Warehouse::Source.find_or_create_by!(name: "ward_toronto") do |s|
  s.url = "https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/5e7a8234-f805-43ac-820f-03d7c360b588/resource/35f67d86-cfc8-4483-8d77-50d035b010d9/download/25-ward-model-december-2018-wgs84-latitude-longitude.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

# Toronto school board wards
Warehouse::Source.find_or_create_by!(name: "sbw_tdsb") do |s|
  s.url = "https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/3b9bbd17-df62-4305-a1e1-1388976f600f/resource/42192109-0a72-48f8-92d5-cd81190432b0/download/toronto-district-school-board-wards-december-2018-wgs84.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "sbw_tcdsb") do |s|
  s.url = "https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/3b9bbd17-df62-4305-a1e1-1388976f600f/resource/49d10010-0eae-47ca-bf78-3158043add96/download/toronto-catholic-district-school-board-wards-december-2018-wgs84.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "sbw_viamonde") do |s|
  s.url = "https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/3b9bbd17-df62-4305-a1e1-1388976f600f/resource/66909b50-1135-4e18-8286-787abb8a355a/download/conseil-scolaire-de-viamonde-french-public-school-board-december-2018-wgs84.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

Warehouse::Source.find_or_create_by!(name: "sbw_monavenir") do |s|
  s.url = "https://ckan0.cf.opendata.inter.prod-toronto.ca/dataset/3b9bbd17-df62-4305-a1e1-1388976f600f/resource/70d55901-8532-4fbc-9b65-6a676ec90c1e/download/conseil-scolaire-de-district-catholique-centre-sud-french-catholic-school-board-december-2018-wg.zip"
  s.format = "shapefile"
  s.fetch_frequency = "manual"
end

# Open Database of Addresses (ODA) — by province
{
  "AB" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_AB_v1.zip",
  "BC" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_BC_v1.zip",
  "MB" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_MB_v1.zip",
  "NB" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_NB_v1.zip",
  "NS" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_NS_v1.zip",
  "NT" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_NT_v1.zip",
  "ON" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_ON_v1.zip",
  "PE" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_PE_v1.zip",
  "QC" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_QC_v1.zip",
  "SK" => "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/ODA_SK_v1.zip"
}.each do |prov, url|
  Warehouse::Source.find_or_create_by!(name: "oda_#{prov.downcase}") do |s|
    s.url = url
    s.format = "csv"
    s.fetch_frequency = "manual"
  end
end

# Economy dashboard sources (CAN-14). Country list: G7 members + OED (the
# World Bank's OECD-members aggregate). Loaders map source codes to
# jurisdictions; the G7 average is computed at import time.
{
  "econ_worldbank_gdp_per_capita_ppp" => "NY.GDP.PCAP.PP.KD",
  "econ_worldbank_gdp_growth" => "NY.GDP.MKTP.KD.ZG",
  "econ_worldbank_trade_balance" => "NE.RSB.GNFS.ZS",
  # CAN-15 Individual Economics & Welfare
  "econ_worldbank_employment_rate" => "SL.EMP.TOTL.SP.ZS",
  "econ_worldbank_age_dependency" => "SP.POP.DPND",
  "econ_worldbank_gini" => "SI.POV.GINI",
  "econ_worldbank_bottom_quintile_income" => "SI.DST.FRST.20",
  # CAN-17 Wellbeing
  "econ_worldbank_fertility_rate" => "SP.DYN.TFRT.IN",
  # CAN-22 Infrastructure & Industrialization
  "econ_worldbank_rd_spending" => "GB.XPD.RSDV.GD.ZS",
  "econ_worldbank_manufacturing_va" => "NV.IND.MANF.ZS",
  "econ_worldbank_broadband" => "IT.NET.BBND.P2",
  "econ_worldbank_rail_freight" => "IS.RRS.GOOD.MT.K6",
  # CAN-24 Environment
  "econ_worldbank_pm25" => "EN.ATM.PM25.MC.M3",
  "econ_worldbank_protected_areas" => "ER.LND.PTLD.ZS",
  "econ_worldbank_forest_area" => "AG.LND.FRST.ZS"
}.each do |name, indicator|
  Warehouse::Source.find_or_create_by!(name: name) do |s|
    s.url = "https://api.worldbank.org/v2/country/CAN;USA;GBR;FRA;DEU;ITA;JPN;OED/indicator/#{indicator}?format=json&per_page=1000"
    s.format = "worldbank_json"
    s.fetch_frequency = "weekly"
  end
end

Warehouse::Source.find_or_create_by!(name: "econ_oecd_labour_productivity") do |s|
  # GDP per hour worked, total economy, USD constant prices PPP (measure GDPHRS,
  # unit USD_PPP_H, price base LR), annual, G7 members + OECD average.
  s.url = "https://sdmx.oecd.org/public/rest/data/OECD.SDD.TPS,DSD_PDB@DF_PDB,/CAN+USA+GBR+FRA+DEU+ITA+JPN+OECD.A.GDPHRS._T.USD_PPP_H.LR.N._Z.PPP?startPeriod=1995&format=csvfile"
  s.format = "csv"
  s.fetch_frequency = "weekly"
end

# CAN-19 Governance — WGI lives in a separate World Bank database (source=3)
# with its own indicator ids, so it can't join the WDI hash above.
Warehouse::Source.find_or_create_by!(name: "econ_worldbank_govt_effectiveness") do |s|
  s.url = "https://api.worldbank.org/v2/country/CAN;USA;GBR;FRA;DEU;ITA;JPN;OED/indicator/GOV_WGI_GE.EST?format=json&per_page=1000&source=3"
  s.format = "worldbank_json"
  s.fetch_frequency = "weekly"
end

# Our World in Data grapher CSVs (loader: OwidEconLoader). Aggregates and
# regions in the files are dropped at import by the ISO3 country mapping.
{
  # CAN-17 Wellbeing
  "econ_owid_life_satisfaction" => "happiness-cantril-ladder",
  # CAN-18 Crime & Public Safety
  "econ_owid_homicide_rate" => "homicide-rate-unodc",
  # CAN-19 Governance
  "econ_owid_corruption_perceptions" => "ti-corruption-perception-index",
  # CAN-24 Environment
  "econ_owid_co2_per_capita" => "co-emissions-per-capita"
}.each do |name, grapher_slug|
  Warehouse::Source.find_or_create_by!(name: name) do |s|
    s.url = "https://ourworldindata.org/grapher/#{grapher_slug}.csv"
    s.format = "csv"
    s.fetch_frequency = "weekly"
  end
end

# CAN-23 International Relations — OECD DAC1 grant-equivalent ODA as % of GNI
# (measure 11002, flow 1160, unit PT_B5G; the series starts in 2018 with the
# grant-equivalent methodology). DAC dataflows use DONOR instead of REF_AREA.
Warehouse::Source.find_or_create_by!(name: "econ_oecd_oda") do |s|
  s.url = "https://sdmx.oecd.org/public/rest/data/OECD.DCD.FSD,DSD_DAC1@DF_DAC1,/CAN+USA+GBR+FRA+DEU+ITA+JPN._Z.11002._Z.1160.PT_B5G.V?startPeriod=2018&format=csvfile"
  s.format = "csv"
  s.fetch_frequency = "weekly"
end

# CAN-18 Crime & Public Safety — StatCan police-reported series (Canada-only).
Warehouse::Source.find_or_create_by!(name: "econ_statcan_crime_severity") do |s|
  # Table 35-10-0026: Crime Severity Index, Canada.
  s.url = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=44312461&latestN=60"
  s.format = "statcan_json"
  s.fetch_frequency = "weekly"
end

Warehouse::Source.find_or_create_by!(name: "econ_statcan_crime_rate") do |s|
  # Table 35-10-0177: Criminal Code violations (excluding traffic), rate per
  # 100,000 population, Canada.
  s.url = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=44407600&latestN=60"
  s.format = "statcan_json"
  s.fetch_frequency = "weekly"
end

# CAN-15 Individual Economics & Welfare — OECD SDMX sources.
Warehouse::Source.find_or_create_by!(name: "econ_oecd_real_minimum_wage") do |s|
  # Real hourly minimum wage, constant prices, USD PPP (measure SM_WG, unit
  # USD_PPP, hourly, price base Q). Italy has no statutory minimum wage, so
  # the computed G7 average never materializes for this measure.
  s.url = "https://sdmx.oecd.org/public/rest/data/OECD.ELS.SAE,DSD_EARNINGS@RMW,/CAN+USA+GBR+FRA+DEU+ITA+JPN.SM_WG.USD_PPP.H.Q._Z._Z?startPeriod=1990&format=csvfile"
  s.format = "csv"
  s.fetch_frequency = "weekly"
end

Warehouse::Source.find_or_create_by!(name: "econ_oecd_hours_worked") do |s|
  # Average annual hours actually worked per worker, total employment
  # (WORKER_STATUS=_T, MEAN), G7 members + OECD average.
  s.url = "https://sdmx.oecd.org/public/rest/data/OECD.ELS.SAE,DSD_HW@DF_AVG_ANN_HRS_WKD,/CAN+USA+GBR+FRA+DEU+ITA+JPN+OECD.HW.H_Y_PS._Z._Z.EMP.A.ACTUAL._T._Z.MEAN._Z._T?startPeriod=1990&format=csvfile"
  s.format = "csv"
  s.fetch_frequency = "weekly"
end

Warehouse::Source.find_or_create_by!(name: "econ_oecd_household_debt") do |s|
  # Household debt as % of net disposable income (NAAG chapter 5, measure
  # LES1M_FD4, unit PT_B6N_S1M), G7 members; no OECD aggregate published.
  s.url = "https://sdmx.oecd.org/public/rest/data/OECD.SDD.NAD,DSD_NAAG@DF_NAAG_V,/A.CAN+USA+GBR+FRA+DEU+ITA+JPN.LES1M_FD4.PT_B6N_S1M.?startPeriod=1995&format=csvfile"
  s.format = "csv"
  s.fetch_frequency = "weekly"
end

# CAN-21 Housing — OECD analytical house prices database.
Warehouse::Source.find_or_create_by!(name: "econ_oecd_house_price_to_income") do |s|
  # Nominal house prices / disposable income per head, % of long-term average
  # (measure HPI_YDH_AVG), G7 members + OECD average.
  s.url = "https://sdmx.oecd.org/public/rest/data/OECD.ECO.MPD,DSD_AN_HOUSE_PRICES@DF_HOUSE_PRICES,/CAN+USA+GBR+FRA+DEU+ITA+JPN+OECD.A.HPI_YDH_AVG.PT_AVG_L_TERM?startPeriod=1990&format=csvfile"
  s.format = "csv"
  s.fetch_frequency = "weekly"
end

Warehouse::Source.find_or_create_by!(name: "econ_oecd_real_house_prices") do |s|
  # CPI-deflated house price index, 2015 = 100 (measure RHP), G7 members +
  # OECD average.
  s.url = "https://sdmx.oecd.org/public/rest/data/OECD.ECO.MPD,DSD_AN_HOUSE_PRICES@DF_HOUSE_PRICES,/CAN+USA+GBR+FRA+DEU+ITA+JPN+OECD.A.RHP.IX?startPeriod=1990&format=csvfile"
  s.format = "csv"
  s.fetch_frequency = "weekly"
end

# CAN-15 — Statistics Canada WDS vector sources (Canada-only series). The
# fetcher normalizes getDataFromVectorsAndLatestNPeriods responses; vector ids
# map to measures in Warehouse::RawIngestion::StatcanEconLoader::VECTORS.
Warehouse::Source.find_or_create_by!(name: "econ_statcan_gini_after_tax") do |s|
  # Table 11-10-0134: Gini coefficient, adjusted after-tax income, Canada.
  s.url = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=96439638&latestN=80"
  s.format = "statcan_json"
  s.fetch_frequency = "weekly"
end

Warehouse::Source.find_or_create_by!(name: "econ_statcan_low_income_dynamics") do |s|
  # Table 11-10-0024: low income entry rate (v96730402) and exit rate
  # (v96730403) of tax filers, Canada, variable low income measure.
  s.url = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=96730402,96730403&latestN=80"
  s.format = "statcan_json"
  s.fetch_frequency = "weekly"
end

# CAN-21 Housing — StatCan-republished CMHC series (Canada-only).
Warehouse::Source.find_or_create_by!(name: "econ_statcan_housing_starts") do |s|
  # Table 34-10-0126: CMHC housing starts, all areas, Canada, total units, annual.
  s.url = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=730579&latestN=80"
  s.format = "statcan_json"
  s.fetch_frequency = "weekly"
end

Warehouse::Source.find_or_create_by!(name: "econ_statcan_rental_vacancy") do |s|
  # Table 34-10-0127: CMHC rental vacancy rate, apartment structures of six
  # units and over, all census metropolitan areas, annual.
  s.url = "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=733334&latestN=60"
  s.format = "statcan_json"
  s.fetch_frequency = "weekly"
end

puts "Seeded #{Warehouse::Source.count} sources"

load Rails.root.join("db/seeds/trade_barriers_jurisdictions.rb")
load Rails.root.join("db/seeds/trade_barriers_themes.rb")
load Rails.root.join("db/seeds/trade_barriers_agreements.rb")

load Rails.root.join("db/seeds/doorkeeper.rb")
