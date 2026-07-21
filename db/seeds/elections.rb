# Elections tracked by the candidate pipeline. Each election needs a
# jurisdiction, an election row (the loaders look elections up by slug and
# never invent dates), and a source pointing at the official candidate feed.

# Keyed by slug — the Toronto jurisdiction may already exist (the KPI loader
# looks it up by slug too) with an environment-specific code.
toronto = Warehouse::Jurisdiction.find_or_create_by!(slug: "toronto") do |j|
  j.name = "City of Toronto"
  j.code = "TOR-ON"
  j.level = "municipal"
  j.fiscal_year_start_month = 1
  j.default_currency = "CAD"
end

Warehouse::Election.find_or_create_by!(slug: "toronto-2026") do |e|
  e.jurisdiction = toronto
  e.name = "Toronto 2026 General Municipal Election"
  e.kind = "municipal"
  e.election_date = Date.new(2026, 10, 26)
  e.nomination_close_date = Date.new(2026, 9, 18)
end

# JSON feeds behind toronto.ca/city-government/elections/candidate-list/.
# The fetcher derives the election year from the trailing digits of the name
# and the loader targets the "toronto-<year>" election above.
Warehouse::Source.find_or_create_by!(name: "election_toronto_2026") do |s|
  s.url = "https://www.toronto.ca/data/elections/candidate_list"
  s.format = "toronto_candidates_json"
  s.fetch_frequency = "daily"
  s.license = "Open Government Licence – Toronto"
  s.attribution = "City of Toronto"
end

puts "Seeded elections: #{Warehouse::Election.count}"
