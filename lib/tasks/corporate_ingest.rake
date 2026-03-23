namespace :data do
  desc "Ingest all corporate registry data (ISED, ODBiz, ODA). No R2 required."
  task ingest_corporate: :environment do
    Rake::Task["db:seed"].invoke

    puts "=== Phase 1: Federal Corporations (ISED XML) ==="
    ingest_source("corporate_federal_ised") do |ingestion, body|
      ingestion.corporate_normalizer.normalize(file_content: body)
      puts "  CorporateEntities: #{CorporateEntity.where(jurisdiction: 'federal').count}"
    end

    puts "\n=== Phase 2: Business Establishments (ODBiz) ==="
    ingest_source("statcan_odbiz") do |ingestion, body|
      ingestion.odbiz_normalizer.normalize(file_content: body)
      puts "  BusinessEstablishments: #{BusinessEstablishment.count}"
    end

    puts "\n=== Phase 3: Addresses (ODA per province) ==="
    Source.where("name LIKE 'statcan_oda_%'").find_each do |source|
      prov = source.name.sub("statcan_oda_", "").upcase
      puts "  Downloading ODA #{prov}..."
      ingest_source(source.name) do |ingestion, body|
        ingestion.oda_normalizer.normalize(file_content: body)
        puts "    #{prov} addresses: #{StandardizedAddress.where(province: prov).count}"
      end
    end

    puts "\n=== Summary ==="
    puts "  CorporateEntities:      #{CorporateEntity.count}"
    puts "  BusinessEstablishments:  #{BusinessEstablishment.count}"
    puts "  StandardizedAddresses:   #{StandardizedAddress.count}"
  end

  desc "Ingest BC OrgBook (API pagination, ~1.6M entities, takes hours)"
  task ingest_bc: :environment do
    Rake::Task["db:seed"].invoke

    puts "=== BC OrgBook API Pagination ==="
    puts "  This will paginate ~1.6M entities. Saves progress, safe to interrupt."
    ingest_source("corporate_bc_orgbook") do |ingestion, _body|
      ingestion.orgbook_bc_normalizer.normalize
      puts "  BC CorporateEntities: #{CorporateEntity.where(jurisdiction: 'bc').count}"
    end
  end

  desc "Ingest federal corporations only (ISED XML, ~500K records, ~1 min)"
  task ingest_federal: :environment do
    Rake::Task["db:seed"].invoke

    puts "=== Federal Corporations (ISED XML) ==="
    ingest_source("corporate_federal_ised") do |ingestion, body|
      ingestion.corporate_normalizer.normalize(file_content: body)
    end

    puts "\n=== Done ==="
    puts "  Federal CorporateEntities: #{CorporateEntity.where(jurisdiction: 'federal').count}"
    statuses = CorporateEntity.where(jurisdiction: "federal").group(:status).count
    statuses.sort_by { |_, v| -v }.each { |s, c| puts "    #{s}: #{c}" }
  end

  desc "Ingest ODBiz business establishments only (~62K records, ~30s)"
  task ingest_odbiz: :environment do
    Rake::Task["db:seed"].invoke

    puts "=== Business Establishments (ODBiz) ==="
    ingest_source("statcan_odbiz") do |ingestion, body|
      ingestion.odbiz_normalizer.normalize(file_content: body)
    end

    puts "\n=== Done ==="
    puts "  BusinessEstablishments: #{BusinessEstablishment.count}"
    provs = BusinessEstablishment.group(:province).count
    provs.sort_by { |_, v| -v }.each { |p, c| puts "    #{p}: #{c}" }
  end

  desc "Ingest ODA addresses for a single province (e.g., rake data:ingest_oda[ab])"
  task :ingest_oda, [:province] => :environment do |_t, args|
    prov = args[:province]&.downcase
    abort "Usage: rake data:ingest_oda[ab]  (province code: ab, bc, on, qc, etc.)" unless prov

    Rake::Task["db:seed"].invoke

    source_name = "statcan_oda_#{prov}"
    source = Source.find_by(name: source_name)
    abort "No source found: #{source_name}. Run db:seed first." unless source

    puts "=== ODA Addresses (#{prov.upcase}) ==="
    ingest_source(source_name) do |ingestion, body|
      ingestion.oda_normalizer.normalize(file_content: body)
    end

    puts "\n=== Done ==="
    puts "  #{prov.upcase} addresses: #{StandardizedAddress.where(province: prov.upcase).count}"
    puts "  Total addresses: #{StandardizedAddress.count}"
  end

  desc "Full pipeline: fiscal + corporate + ODBiz + ODA (everything)"
  task ingest_all: :environment do
    puts "=== Full York Factory Ingest ==="
    puts "  This will download and process all data sources."
    puts "  Estimated time: ~30 min (depending on network)"
    puts ""

    Rake::Task["data:seed"].invoke
    puts ""
    Rake::Task["data:ingest_corporate"].invoke

    puts "\n=== Complete Pipeline Summary ==="
    puts "  GovernmentEntities:     #{GovernmentEntity.count}"
    puts "  GovernmentEntityAliases:#{GovernmentEntityAlias.count}"
    puts "  FiscalAuthorities:      #{FiscalAuthority.count}"
    puts "  FiscalExpenditures:     #{FiscalExpenditure.count}"
    puts "  CorporateEntities:      #{CorporateEntity.count}"
    puts "  BusinessEstablishments: #{BusinessEstablishment.count}"
    puts "  StandardizedAddresses:  #{StandardizedAddress.count}"
    puts ""
    puts "  Next steps:"
    puts "    rake data:ingest_bc     # BC OrgBook (1.6M entities, hours)"
    puts "    bin/rails console       # Manual: Source.find_by!(name: 'corporate_on_obr').fetcher.fetch_later"
  end
end

def ingest_source(source_name)
  source = Source.find_by!(name: source_name)
  puts "  Downloading #{source.url}"

  http = HTTPX.plugin(:follow_redirects)
  response = http.get(source.url)
  raise "HTTP #{response.status} fetching #{source.url}" unless response.status == 200
  body = response.body.to_s

  checksum = Digest::SHA256.hexdigest(body)
  if source.raw_ingestions.exists?(checksum: checksum)
    puts "  Data unchanged (checksum match), skipping"
    return
  end

  ingestion = source.raw_ingestions.create!(
    fetched_at: Time.current,
    raw_file_path: "local/#{source.name}/#{Date.current.iso8601}",
    checksum: checksum,
    status: :pending
  )

  t = Time.now
  yield(ingestion, body)
  elapsed = Time.now - t

  ingestion.reload
  puts "  Status: #{ingestion.status} (#{elapsed.round(1)}s)"
rescue => e
  puts "  ERROR: #{e.message}"
  raise
end
