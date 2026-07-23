require "csv"

namespace :postal_codes do
  R2_KEY = "misc_data/CanadianPostalCodes202403.csv"

  desc "Import postal code centroids from a CanadianPostalCodes CSV (default: download #{R2_KEY} from R2)"
  task :import, [ :path ] => :environment do |_t, args|
    tempfile = nil
    if args[:path]
      path = args[:path]
      abort "File not found: #{path}" unless File.exist?(path)
    else
      tempfile = Tempfile.new([ "postal_codes", ".csv" ])
      puts "Downloading #{R2_KEY} from R2..."
      R2Storage.new.download_to(key: R2_KEY, path: tempfile.path)
      path = tempfile.path
    end

    conn = ActiveRecord::Base.connection.raw_connection
    now = Time.current.utc.iso8601(6)
    count = 0
    skipped = 0
    seen = Set.new

    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("TRUNCATE warehouse.postal_codes RESTART IDENTITY")

      conn.copy_data(<<~SQL) do
        COPY warehouse.postal_codes (postal_code, city, province_code, time_zone_offset, latitude, longitude, created_at, updated_at)
        FROM STDIN WITH (FORMAT csv)
      SQL
        CSV.foreach(path, headers: true) do |row|
          postal_code = Warehouse::PostalCode.normalize(row["POSTAL_CODE"])
          if postal_code.nil? || row["LATITUDE"].blank? || row["LONGITUDE"].blank? || !seen.add?(postal_code)
            skipped += 1
            next
          end

          conn.put_copy_data(CSV.generate_line([
            postal_code,
            row["CITY"],
            row["PROVINCE_ABBR"],
            row["TIME_ZONE"],
            row["LATITUDE"],
            row["LONGITUDE"],
            now,
            now
          ]))
          count += 1
          puts "  #{count} rows..." if (count % 100_000).zero?
        end
      end
    end

    puts "Imported #{count} postal codes (#{skipped} rows skipped). Total: #{Warehouse::PostalCode.count}"
  ensure
    tempfile&.close!
  end
end
