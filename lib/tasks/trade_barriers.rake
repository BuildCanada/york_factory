require "json"

namespace :trade_barriers do
  desc "Import legacy Supabase trade barriers data from tmp/trade-barriers/*.sql"
  task import: :environment do
    sql_dir = Rails.root.join("tmp", "trade-barriers")
    abort "Missing #{sql_dir}" unless File.directory?(sql_dir)

    AGREEMENT_STATUS_MAP = {
      "Awaiting Sponsorship"    => "awaiting_sponsorship",
      "Under Negotiation"       => "under_negotiation",
      "Agreement Reached"       => "agreement_reached",
      "Partially Implemented"   => "partially_implemented",
      "Implemented"             => "implemented",
      "Deferred"                => "deferred"
    }

    JURISDICTION_STATUS_MAP = {
      "Unknown"        => "unknown",
      "Aware"          => "aware",
      "Considering"    => "considering",
      "Engaged"        => "engaged",
      "Committed"      => "committed",
      "Implementing"   => "implementing",
      "Complete"       => "complete",
      "Declined"       => "declined",
      "Not Applicable" => "not_applicable"
    }

    # Make sure jurisdictions and themes are seeded.
    load Rails.root.join("db/seeds/trade_barriers_jurisdictions.rb")
    load Rails.root.join("db/seeds/trade_barriers_themes.rb")

    # Load any themes from the dump that aren't in our seeded list.
    themes_sql = File.read(sql_dir.join("themes_rows.sql"))
    themes_sql.scan(/\((\d+),\s*'([^']+)'\)/).each do |_id, name|
      TradeBarriers::Theme.find_or_create_by!(name: name)
    end

    # Load agreements via temp table so we don't need a fragile parser.
    conn = ActiveRecord::Base.connection
    conn.execute("DROP TABLE IF EXISTS pg_temp.legacy_agreements")
    # NOTE: jurisdictions/agreement_history are TEXT (not jsonb) because the
    # Supabase dump escapes embedded quotes as \" rather than the doubled
    # quotes Postgres' JSON parser expects. We parse them with Ruby's JSON
    # library below, which handles standard JSON escapes correctly.
    conn.execute(<<~SQL)
      CREATE TEMP TABLE legacy_agreements (
        id integer,
        title text,
        summary text,
        description text,
        jurisdictions text,
        deadline date,
        status text,
        source_url text,
        created_at timestamptz,
        updated_at timestamptz,
        launch_date date,
        agreement_history text,
        theme text
      )
    SQL

    raw = File.read(sql_dir.join("agreements_rows.sql"))
    raw = raw.gsub('"public"."agreements"', "legacy_agreements")
    conn.execute(raw)

    # The dump double-escapes backslashes, so embedded JSON quotes appear as
    # \\" instead of \". Undo one level so JSON.parse sees valid input.
    unescape = ->(s) { s.nil? ? nil : s.gsub('\\\\') { '\\' } }

    rows = conn.execute("SELECT * FROM legacy_agreements ORDER BY id")
    imported = 0
    rows.each do |row|
      theme = row["theme"].present? ? TradeBarriers::Theme.find_by(name: row["theme"]) : nil
      if row["theme"].present? && !theme
        warn "Agreement #{row['id']}: unknown theme #{row['theme'].inspect}; importing without theme"
      end

      status = AGREEMENT_STATUS_MAP[row["status"]]
      unless status
        warn "Skipping agreement #{row['id']}: unknown status #{row['status'].inspect}"
        next
      end

      agreement = TradeBarriers::Agreement.find_or_initialize_by(id: row["id"])
      agreement.assign_attributes(
        title: row["title"],
        summary: row["summary"],
        description: row["description"],
        deadline: row["deadline"],
        launch_date: row["launch_date"],
        source_url: row["source_url"],
        status: status,
        theme: theme
      )
      agreement.save!

      # Replace agreement-level history.
      agreement.histories.delete_all
      JSON.parse(unescape.call(row["agreement_history"]) || "[]").each do |h|
        mapped = AGREEMENT_STATUS_MAP[h["status"]] || h["status"]
        agreement.histories.create!(status: mapped, date_entered: h["date_entered"])
      end

      # Replace jurisdictions and per-jurisdiction history.
      agreement.agreement_jurisdictions.destroy_all
      JSON.parse(unescape.call(row["jurisdictions"]) || "[]").each do |j|
        jurisdiction = Warehouse::Jurisdiction.find_by(name: j["name"])
        unless jurisdiction
          warn "Agreement #{row['id']}: unknown jurisdiction #{j['name'].inspect}"
          next
        end

        aj_status = JURISDICTION_STATUS_MAP[j["status"]] || "unknown"
        aj = agreement.agreement_jurisdictions.create!(
          jurisdiction: jurisdiction,
          status: aj_status,
          notes: j["notes"]
        )
        Array(j["jurisdiction_history"]).each do |h|
          mapped = JURISDICTION_STATUS_MAP[h["status"]] || h["status"]
          aj.histories.create!(status: mapped, date_entered: h["date_entered"])
        end
      end

      imported += 1
    end

    # Reset the agreements pkey sequence so future creates don't collide with imported ids.
    conn.execute(<<~SQL)
      SELECT setval(
        pg_get_serial_sequence('trade_barriers_agreements', 'id'),
        COALESCE((SELECT MAX(id) FROM trade_barriers_agreements), 0) + 1,
        false
      )
    SQL

    puts "Imported #{imported} trade barriers agreements"
  end
end
