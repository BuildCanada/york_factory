namespace :economy do
  desc "Fetch all economy dashboard sources (econ_*) synchronously"
  task fetch_all: :environment do
    sources = Warehouse::Source.where("name LIKE 'econ\\_%'").order(:name)
    abort "No economy sources found. Run bin/rails db:seed first." if sources.empty?

    failures = 0
    sources.each do |source|
      puts "Fetching #{source.name}..."
      begin
        source.fetcher.fetch
      rescue => e
        failures += 1
        puts "  FAILED: #{e.message}"
      end
    end

    puts "Done (#{sources.size - failures}/#{sources.size} succeeded)."
    exit(1) if failures.positive?
  end

  desc "Show fetch/ingestion status for economy sources"
  task status: :environment do
    Warehouse::Source.where("name LIKE 'econ\\_%'").order(:name).each do |source|
      ingestion = source.raw_ingestions.order(fetched_at: :desc).first
      observations = Warehouse::ExtractedObservation
        .joins("JOIN warehouse.kpi_documents d ON d.id = warehouse.extracted_observations.document_id")
        .joins("JOIN warehouse.raw_ingestions ri ON ri.id = d.raw_ingestion_id")
        .where(ri: { source_id: source.id })
        .count

      puts "%-40s last_fetched=%-12s ingestion=%-10s observations=%d" % [
        source.name,
        source.last_fetched_at&.to_date || "never",
        ingestion&.status || "-",
        observations
      ]
    end
  end
end
