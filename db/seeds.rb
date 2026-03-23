# Seed data sources for York Factory pipeline

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

puts "Seeded #{Source.count} sources"
