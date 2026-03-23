# Seed data sources for York Factory pipeline

# Existing fiscal data sources
Source.find_or_create_by!(name: "infobase_authorities") do |s|
  s.url = "https://open.canada.ca/data/dataset/a35cf382-690c-4221-a971-cf0fd189a46f/resource/3bafde71-8cb8-460e-93e2-691295221063/download/eav_eac_en.csv"
  s.format = "csv"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "estimates_main_2025_26") do |s|
  s.url = "https://www.canada.ca/content/dam/tbs-sct/documents/planned-government-spending/main-estimates/2025-26/organization-summary.csv"
  s.format = "csv"
  s.fetch_frequency = "manual"
end

# Corporate registry sources
Source.find_or_create_by!(name: "corporate_federal_ised") do |s|
  s.url = "https://ised-isde.canada.ca/cc/lgcy/download/OPEN_DATA_SPLIT.zip"
  s.format = "xml_zip"
  s.fetch_frequency = "weekly"
end

Source.find_or_create_by!(name: "corporate_bc_orgbook") do |s|
  s.url = "https://orgbook.gov.bc.ca/api/v4/search/topic"
  s.format = "json_api"
  s.fetch_frequency = "weekly"
end

Source.find_or_create_by!(name: "corporate_qc_req") do |s|
  s.url = "https://www.donneesquebec.ca/recherche/dataset/registre-des-entreprises"
  s.format = "csv_zip"
  s.fetch_frequency = "bimonthly"
end

Source.find_or_create_by!(name: "corporate_on_obr") do |s|
  s.url = "https://www.ontario.ca/page/ontario-business-registry"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_ab_cores") do |s|
  s.url = "https://cores.reg.gov.ab.ca"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_sk_isc") do |s|
  s.url = "https://corporateregistry.isc.ca"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_ns_rjsc") do |s|
  s.url = "https://rjsc.novascotia.ca"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_nb_snb") do |s|
  s.url = "https://www2.snb.ca/content/snb/en/sites/corporate-registry.html"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_mb_companies") do |s|
  s.url = "https://companiesoffice.gov.mb.ca"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_pe_registry") do |s|
  s.url = "https://www.princeedwardisland.ca/en/service/corporate-business-names-registry"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_nl_cado") do |s|
  s.url = "https://cado-gsc.ca"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_yt_affairs") do |s|
  s.url = "https://yukon.ca/en/doing-business/starting-business/register-business"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_nt_registries") do |s|
  s.url = "https://www.justice.gov.nt.ca/en/divisions/legal-registries/"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

Source.find_or_create_by!(name: "corporate_nu_registries") do |s|
  s.url = "https://www.gov.nu.ca/justice"
  s.format = "html_scrape"
  s.fetch_frequency = "manual"
end

# Statistics Canada ODBiz (Open Database of Businesses)
Source.find_or_create_by!(name: "statcan_odbiz") do |s|
  s.url = "https://www150.statcan.gc.ca/n1/pub/21-26-0003/2023001/ODBus_2023.zip"
  s.format = "csv_zip"
  s.fetch_frequency = "quarterly"
end

# Statistics Canada ODA (Open Database of Addresses) — per province
{
  "AB" => "ODA_AB_v1", "BC" => "ODA_BC_v1", "MB" => "ODA_MB_v1",
  "NB" => "ODA_NB_v1", "NS" => "ODA_NS_v1", "NT" => "ODA_NT_v1",
  "ON" => "ODA_ON_v1", "PE" => "ODA_PE_v1", "QC" => "ODA_QC_v1",
  "SK" => "ODA_SK_v1"
}.each do |prov, filename|
  Source.find_or_create_by!(name: "statcan_oda_#{prov.downcase}") do |s|
    s.url = "https://www150.statcan.gc.ca/n1/en/pub/46-26-0001/2021001/#{filename}.zip"
    s.format = "csv_zip"
    s.fetch_frequency = "annual"
  end
end

puts "Seeded #{Source.count} sources"
