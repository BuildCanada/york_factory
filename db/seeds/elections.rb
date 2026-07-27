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

brampton = Warehouse::Jurisdiction.find_or_create_by!(slug: "brampton") do |j|
  j.name = "City of Brampton"
  j.code = "BRM-ON"
  j.level = "municipal"
  j.fiscal_year_start_month = 1
  j.default_currency = "CAD"
end

Warehouse::Election.find_or_create_by!(slug: "brampton-2026") do |e|
  e.jurisdiction = brampton
  e.name = "Brampton 2026 General Municipal Election"
  e.kind = "municipal"
  e.election_date = Date.new(2026, 10, 26)
  e.nomination_close_date = Date.new(2026, 8, 21)
end

# Brampton publishes no candidate feed, so the fetcher scrapes the candidate
# listing page itself and normalizes it to JSON before the loader runs.
Warehouse::Source.find_or_create_by!(name: "election_brampton_2026") do |s|
  s.url = "https://www.brampton.ca/EN/City-Hall/Election/Candidates/Pages/candidateListing.aspx"
  s.format = "brampton_candidates_html"
  s.fetch_frequency = "daily"
  s.attribution = "City of Brampton"
end

hamilton = Warehouse::Jurisdiction.find_or_create_by!(slug: "hamilton") do |j|
  j.name = "City of Hamilton"
  j.code = "HAM-ON"
  j.level = "municipal"
  j.fiscal_year_start_month = 1
  j.default_currency = "CAD"
end

Warehouse::Election.find_or_create_by!(slug: "hamilton-2026") do |e|
  e.jurisdiction = hamilton
  e.name = "Hamilton 2026 General Municipal Election"
  e.kind = "municipal"
  e.election_date = Date.new(2026, 10, 26)
  e.nomination_close_date = Date.new(2026, 8, 21)
end

# Hamilton publishes no candidate feed either: mayor, 15 councillor wards, and
# the trustee districts all live on one page, which the fetcher scrapes and
# normalizes to JSON before the loader runs.
Warehouse::Source.find_or_create_by!(name: "election_hamilton_2026") do |s|
  s.url = "https://www.hamilton.ca/city-council/municipal-election/candidates-third-party-advertisers/candidates"
  s.format = "hamilton_candidates_html"
  s.fetch_frequency = "daily"
  s.attribution = "City of Hamilton"
end

puts "Seeded elections: #{Warehouse::Election.count}"
