# Canadian jurisdictions used by the trade barriers tracker.
[
  { code: "CA", name: "Canada",                    level: "federal" },
  { code: "AB", name: "Alberta",                   level: "provincial" },
  { code: "BC", name: "British Columbia",          level: "provincial" },
  { code: "MB", name: "Manitoba",                  level: "provincial" },
  { code: "NB", name: "New Brunswick",             level: "provincial" },
  { code: "NL", name: "Newfoundland and Labrador", level: "provincial" },
  { code: "NS", name: "Nova Scotia",               level: "provincial" },
  { code: "ON", name: "Ontario",                   level: "provincial" },
  { code: "PE", name: "Prince Edward Island",      level: "provincial" },
  { code: "QC", name: "Quebec",                    level: "provincial" },
  { code: "SK", name: "Saskatchewan",              level: "provincial" },
  { code: "NT", name: "Northwest Territories",     level: "territorial" },
  { code: "NU", name: "Nunavut",                   level: "territorial" },
  { code: "YT", name: "Yukon",                     level: "territorial" }
].each do |attrs|
  Warehouse::Jurisdiction.find_or_create_by!(code: attrs[:code]) do |j|
    j.name = attrs[:name]
    j.level = attrs[:level]
    j.slug = attrs[:name].parameterize
    j.fiscal_year_start_month = 4
    j.default_currency = "CAD"
  end
end

puts "Seeded #{Warehouse::Jurisdiction.count} jurisdictions"
