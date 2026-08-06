namespace :spending do
  desc "Fetch all non-manual spending sources synchronously"
  task fetch_all: :environment do
    sources = Warehouse::Source.where("name LIKE 'spending\\_%'")
      .where.not(fetch_frequency: "manual").order(:name)
    abort "No spending sources found. Run bin/rails db:seed first." if sources.empty?

    failures = 0
    sources.each do |source|
      puts "Fetching #{source.name}..."
      source.fetcher.fetch
    rescue => error
      failures += 1
      warn "  FAILED: #{error.message}"
    end

    puts "Done (#{sources.size - failures}/#{sources.size} succeeded)."
    abort "#{failures} spending source(s) failed" if failures.positive?
  end

  desc "Import a scraper snapshot: spending:import_snapshot[source_name,path,full_snapshot]"
  task :import_snapshot, [ :source_name, :path, :full_snapshot ] => :environment do |_task, args|
    source_name = args[:source_name].presence || abort("source_name is required")
    snapshot_path = args[:path].presence || abort("path is required")
    source = Warehouse::Source.find_by!(name: source_name)
    path = Pathname(snapshot_path).expand_path
    abort "Snapshot not found: #{path}" unless path.file?

    checksum = Digest::SHA256.file(path).hexdigest
    ingestion = source.raw_ingestions.find_or_initialize_by(checksum: checksum)
    if ingestion.persisted? && !ingestion.failed?
      abort "Snapshot already imported as ingestion #{ingestion.id} (#{ingestion.status})"
    end

    ingestion.update!(
      fetched_at: Time.current,
      raw_file_path: path.to_s,
      status: :pending,
      error_message: nil
    )

    File.open(path, "r:bom|utf-8", newline: :universal) do |file|
      body = path.extname.casecmp?(".csv") ? file : file.read
      result = ingestion.spending_loader.load(body: body, withdraw_missing: args[:full_snapshot] == "true")
      puts "Imported #{result.total} rows (#{result.created} created, #{result.updated} updated, " \
        "#{result.unchanged} unchanged, #{result.withdrawn} withdrawn)."
    end
  end
end
