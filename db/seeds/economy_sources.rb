# Economy dashboard sources (CAN-14+). Country list: G7 members + OED (the
# World Bank's OECD-members aggregate). Loaders map source codes to
# jurisdictions; the G7 average is computed at import time.
#
# Each source records the license its data is redistributed under and the
# attribution line dashboards must display alongside the data (OWID's
# CC BY 4.0 requires attribution; StatCan/World Bank/OECD open licenses
# require source acknowledgment). License and attribution are re-applied on
# every seed run so existing rows pick up changes.

econ_source = lambda do |name, url:, format:, license:, attribution:, frequency: "weekly"|
  source = Warehouse::Source.find_or_create_by!(name: name) do |s|
    s.url = url
    s.format = format
    s.fetch_frequency = frequency
  end
  source.update!(license: license, attribution: attribution)
end

worldbank_terms = {
  license: "CC BY 4.0",
  attribution: "World Bank Open Data (data.worldbank.org), CC BY 4.0"
}
oecd_terms = {
  license: "OECD Terms and Conditions",
  attribution: "OECD Data Explorer (data-explorer.oecd.org)"
}
owid_terms = {
  license: "CC BY 4.0",
  attribution: "Our World in Data (ourworldindata.org), CC BY 4.0; underlying data from original providers"
}
statcan_terms = {
  license: "Statistics Canada Open Licence",
  attribution: "Adapted from Statistics Canada; this does not constitute an endorsement by Statistics Canada"
}

{
  "econ_worldbank_gdp_per_capita_ppp" => "NY.GDP.PCAP.PP.KD",
  "econ_worldbank_gdp_growth" => "NY.GDP.MKTP.KD.ZG",
  "econ_worldbank_trade_balance" => "NE.RSB.GNFS.ZS",
  "econ_worldbank_inflation" => "FP.CPI.TOTL.ZG",
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
  econ_source.call(
    name,
    url: "https://api.worldbank.org/v2/country/CAN;USA;GBR;FRA;DEU;ITA;JPN;OED/indicator/#{indicator}?format=json&per_page=1000",
    format: "worldbank_json",
    **worldbank_terms
  )
end

# GDP per hour worked, total economy, USD constant prices PPP (measure GDPHRS,
# unit USD_PPP_H, price base LR), annual, G7 members + OECD average.
econ_source.call(
  "econ_oecd_labour_productivity",
  url: "https://sdmx.oecd.org/public/rest/data/OECD.SDD.TPS,DSD_PDB@DF_PDB,/CAN+USA+GBR+FRA+DEU+ITA+JPN+OECD.A.GDPHRS._T.USD_PPP_H.LR.N._Z.PPP?startPeriod=1995&format=csvfile",
  format: "csv",
  **oecd_terms
)

# CAN-19 Governance — WGI lives in a separate World Bank database (source=3)
# with its own indicator ids, so it can't join the WDI hash above.
econ_source.call(
  "econ_worldbank_govt_effectiveness",
  url: "https://api.worldbank.org/v2/country/CAN;USA;GBR;FRA;DEU;ITA;JPN;OED/indicator/GOV_WGI_GE.EST?format=json&per_page=1000&source=3",
  format: "worldbank_json",
  **worldbank_terms
)

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
  econ_source.call(
    name,
    url: "https://ourworldindata.org/grapher/#{grapher_slug}.csv",
    format: "csv",
    **owid_terms
  )
end

# CAN-23 International Relations — OECD DAC1 grant-equivalent ODA as % of GNI
# (measure 11002, flow 1160, unit PT_B5G; the series starts in 2018 with the
# grant-equivalent methodology). DAC dataflows use DONOR instead of REF_AREA.
econ_source.call(
  "econ_oecd_oda",
  url: "https://sdmx.oecd.org/public/rest/data/OECD.DCD.FSD,DSD_DAC1@DF_DAC1,/CAN+USA+GBR+FRA+DEU+ITA+JPN._Z.11002._Z.1160.PT_B5G.V?startPeriod=2018&format=csvfile",
  format: "csv",
  **oecd_terms
)

# CAN-14 Overall Economy — Canadian-source real-time GDP (Canada-only).
# Table 36-10-0434: real GDP at basic prices, all industries, monthly,
# seasonally adjusted at annual rates, chained 2017 $ millions.
# latestN=400 covers the full series (monthly since 1997).
econ_source.call(
  "econ_statcan_gdp_monthly",
  url: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=65201210&latestN=400",
  format: "statcan_json",
  **statcan_terms
)

# Cost of living — monthly CPI for Canadian essentials (Canada-only).
# Table 18-10-0004: CPI monthly, not seasonally adjusted, 2002=100, Canada.
# Vectors: all-items, food, shelter, rent, clothing and footwear,
# transportation, gasoline, energy. latestN=400 covers ~33 years of months.
econ_source.call(
  "econ_statcan_cpi_essentials",
  url: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=41690973,41690974,41691050,41691052,41691108,41691128,41691136,41691239&latestN=400",
  format: "statcan_json",
  **statcan_terms
)

# CAN-18 Crime & Public Safety — StatCan police-reported series (Canada-only).
# Table 35-10-0026: Crime Severity Index, Canada.
econ_source.call(
  "econ_statcan_crime_severity",
  url: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=44312461&latestN=60",
  format: "statcan_json",
  **statcan_terms
)

# Table 35-10-0177: Criminal Code violations (excluding traffic), rate per
# 100,000 population, Canada.
econ_source.call(
  "econ_statcan_crime_rate",
  url: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=44407600&latestN=60",
  format: "statcan_json",
  **statcan_terms
)

# CAN-15 Individual Economics & Welfare — OECD SDMX sources.
# Real hourly minimum wage, constant prices, USD PPP (measure SM_WG, unit
# USD_PPP, hourly, price base Q). Italy has no statutory minimum wage, so
# the computed G7 average never materializes for this measure.
econ_source.call(
  "econ_oecd_real_minimum_wage",
  url: "https://sdmx.oecd.org/public/rest/data/OECD.ELS.SAE,DSD_EARNINGS@RMW,/CAN+USA+GBR+FRA+DEU+ITA+JPN.SM_WG.USD_PPP.H.Q._Z._Z?startPeriod=1990&format=csvfile",
  format: "csv",
  **oecd_terms
)

# Average annual hours actually worked per worker, total employment
# (WORKER_STATUS=_T, MEAN), G7 members + OECD average.
econ_source.call(
  "econ_oecd_hours_worked",
  url: "https://sdmx.oecd.org/public/rest/data/OECD.ELS.SAE,DSD_HW@DF_AVG_ANN_HRS_WKD,/CAN+USA+GBR+FRA+DEU+ITA+JPN+OECD.HW.H_Y_PS._Z._Z.EMP.A.ACTUAL._T._Z.MEAN._Z._T?startPeriod=1990&format=csvfile",
  format: "csv",
  **oecd_terms
)

# Household debt as % of net disposable income (NAAG chapter 5, measure
# LES1M_FD4, unit PT_B6N_S1M), G7 members; no OECD aggregate published.
econ_source.call(
  "econ_oecd_household_debt",
  url: "https://sdmx.oecd.org/public/rest/data/OECD.SDD.NAD,DSD_NAAG@DF_NAAG_V,/A.CAN+USA+GBR+FRA+DEU+ITA+JPN.LES1M_FD4.PT_B6N_S1M.?startPeriod=1995&format=csvfile",
  format: "csv",
  **oecd_terms
)

# CAN-21 Housing — OECD analytical house prices database.
# Nominal house prices / disposable income per head, % of long-term average
# (measure HPI_YDH_AVG), G7 members + OECD average.
econ_source.call(
  "econ_oecd_house_price_to_income",
  url: "https://sdmx.oecd.org/public/rest/data/OECD.ECO.MPD,DSD_AN_HOUSE_PRICES@DF_HOUSE_PRICES,/CAN+USA+GBR+FRA+DEU+ITA+JPN+OECD.A.HPI_YDH_AVG.PT_AVG_L_TERM?startPeriod=1990&format=csvfile",
  format: "csv",
  **oecd_terms
)

# CPI-deflated house price index, 2015 = 100 (measure RHP), G7 members +
# OECD average.
econ_source.call(
  "econ_oecd_real_house_prices",
  url: "https://sdmx.oecd.org/public/rest/data/OECD.ECO.MPD,DSD_AN_HOUSE_PRICES@DF_HOUSE_PRICES,/CAN+USA+GBR+FRA+DEU+ITA+JPN+OECD.A.RHP.IX?startPeriod=1990&format=csvfile",
  format: "csv",
  **oecd_terms
)

# CAN-15 — Statistics Canada WDS vector sources (Canada-only series). The
# fetcher normalizes getDataFromVectorsAndLatestNPeriods responses; vector ids
# map to measures in Warehouse::RawIngestion::StatcanEconLoader::VECTORS.
# Table 11-10-0134: Gini coefficient, adjusted after-tax income, Canada.
econ_source.call(
  "econ_statcan_gini_after_tax",
  url: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=96439638&latestN=80",
  format: "statcan_json",
  **statcan_terms
)

# Table 11-10-0024: low income entry rate (v96730402) and exit rate
# (v96730403) of tax filers, Canada, variable low income measure.
econ_source.call(
  "econ_statcan_low_income_dynamics",
  url: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=96730402,96730403&latestN=80",
  format: "statcan_json",
  **statcan_terms
)

# CAN-21 Housing — StatCan-republished CMHC series (Canada-only).
# Table 34-10-0126: CMHC housing starts, all areas, Canada, total units, annual.
econ_source.call(
  "econ_statcan_housing_starts",
  url: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=730579&latestN=80",
  format: "statcan_json",
  **statcan_terms
)

# Table 34-10-0127: CMHC rental vacancy rate, apartment structures of six
# units and over, all census metropolitan areas, annual.
econ_source.call(
  "econ_statcan_rental_vacancy",
  url: "https://www150.statcan.gc.ca/t1/wds/rest/getDataFromVectorsAndLatestNPeriods?vectors=733334&latestN=60",
  format: "statcan_json",
  **statcan_terms
)
