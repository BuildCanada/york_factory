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

load Rails.root.join("db/seeds/economy_sources.rb")
Search::Media::FeedCatalog.provision!

puts "Seeded #{Warehouse::Source.count} sources"

load Rails.root.join("db/seeds/trade_barriers_jurisdictions.rb")
load Rails.root.join("db/seeds/elections.rb")
load Rails.root.join("db/seeds/trade_barriers_themes.rb")
load Rails.root.join("db/seeds/trade_barriers_agreements.rb")
load Rails.root.join("db/seeds/doorkeeper.rb")

# Sample memo + engagements are development-only fixtures (production memos come
# from the Webflow export). Guard against seeding fake data into production.
load Rails.root.join("db/seeds/memo_engagements.rb") if Rails.env.development?
