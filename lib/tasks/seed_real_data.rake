require "csv"

namespace :data do
  desc "Fetch and load real InfoBase + Estimates data (no R2 required)"
  task seed: :environment do
    # Ensure sources exist
    Rake::Task["db:seed"].invoke

    puts "=== Fetching InfoBase authorities/expenditures ==="
    infobase_source = Source.find_by!(name: "infobase_authorities")
    infobase_body = fetch_csv(infobase_source.url)
    infobase_ingestion = create_ingestion(infobase_source, infobase_body)

    puts "  Loading #{infobase_body.lines.count - 1} rows..."
    infobase_ingestion.infobase_loader.load(csv_content: infobase_body)
    infobase_ingestion.reload
    puts "  Status: #{infobase_ingestion.status}"
    puts "  Organizations: #{Organization.count}"
    puts "  Fiscal Expenditures: #{FiscalExpenditure.count}"

    puts "\n=== Fetching Main Estimates 2025-26 ==="
    estimates_source = Source.find_by!(name: "estimates_main_2025_26")
    estimates_body = fetch_csv(estimates_source.url)
    estimates_ingestion = create_ingestion(estimates_source, estimates_body)

    puts "  Loading #{estimates_body.lines.count - 1} rows..."
    estimates_ingestion.estimates_normalizer.normalize(csv_content: estimates_body)
    estimates_ingestion.reload
    puts "  Status: #{estimates_ingestion.status}"
    puts "  Fiscal Authorities: #{FiscalAuthority.count}"
    puts "  Lineage Entries: #{LineageEntry.count}"
    puts "  Low confidence: #{LineageEntry.where('confidence < 0.8').where.not(confidence: nil).count}"

    puts "\n=== Summary ==="
    puts "  Organizations:          #{Organization.count}"
    puts "  Organization Aliases:   #{OrganizationAlias.count}"
    puts "  Fiscal Expenditures:    #{FiscalExpenditure.count}"
    puts "  Fiscal Authorities:     #{FiscalAuthority.count}"
    puts "  Lineage Entries:        #{LineageEntry.count}"
  end

  desc "Load InfoBase data only (no Estimates, no LLM calls)"
  task seed_infobase: :environment do
    Rake::Task["db:seed"].invoke

    puts "=== Fetching InfoBase authorities/expenditures ==="
    source = Source.find_by!(name: "infobase_authorities")
    body = fetch_csv(source.url)
    ingestion = create_ingestion(source, body)

    puts "  Loading #{body.lines.count - 1} rows..."
    ingestion.infobase_loader.load(csv_content: body)
    ingestion.reload

    puts "\n=== Done ==="
    puts "  Status: #{ingestion.status}"
    puts "  Organizations: #{Organization.count}"
    puts "  Organization Aliases: #{OrganizationAlias.count}"
    puts "  Fiscal Expenditures: #{FiscalExpenditure.count}"
    puts "  Lineage Entries: #{LineageEntry.count}"
  end

  desc "Load Estimates data only (requires InfoBase orgs loaded first for entity resolution)"
  task seed_estimates: :environment do
    if Organization.count == 0
      puts "No organizations found. Run `rake data:seed_infobase` first."
      exit 1
    end

    Rake::Task["db:seed"].invoke

    puts "=== Fetching Main Estimates 2025-26 ==="
    source = Source.find_by!(name: "estimates_main_2025_26")
    body = fetch_csv(source.url)
    ingestion = create_ingestion(source, body)

    puts "  Loading #{body.lines.count - 1} rows..."
    ingestion.estimates_normalizer.normalize(csv_content: body)
    ingestion.reload

    puts "\n=== Done ==="
    puts "  Status: #{ingestion.status}"
    puts "  Fiscal Authorities: #{FiscalAuthority.count}"
    puts "  Low confidence: #{LineageEntry.where('confidence < 0.8').where.not(confidence: nil).count}"
  end
end

def fetch_csv(url)
  puts "  Downloading #{url}"
  http = HTTPX.plugin(:follow_redirects)
  response = http.get(url)
  raise "HTTP #{response.status} fetching #{url}" unless response.status == 200
  response.body.to_s
end

def create_ingestion(source, body)
  checksum = Digest::SHA256.hexdigest(body)
  source.raw_ingestions.find_or_create_by!(checksum: checksum) do |i|
    i.fetched_at = Time.current
    i.raw_file_path = "local/#{source.name}/#{Date.current.iso8601}"
    i.status = :pending
  end
end
