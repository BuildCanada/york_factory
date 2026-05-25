namespace :kpis do
  desc "Seed KPI reference data (jurisdictions, units, organizations, lineages) from db/seeds/kpis/*.yml"
  task seed_reference: :environment do
    require "yaml"

    seed_dir = Rails.root.join("db/seeds/kpis")

    ActiveRecord::Base.transaction do
      seed_toronto_jurisdiction
      units_seeded = seed_units(seed_dir.join("units.yml"))
      orgs_seeded, aliases_seeded = seed_toronto_organizations(seed_dir.join("toronto_organizations.yml"))
      lineages_seeded = seed_toronto_organization_lineages(seed_dir.join("toronto_organization_lineages.yml"))

      puts "Seeded:"
      puts "  units:                  #{units_seeded}"
      puts "  organizations:          #{orgs_seeded}"
      puts "  organization_aliases:   #{aliases_seeded}"
      puts "  organization_lineages:  #{lineages_seeded}"
    end
  end

  desc "Import one-time Toronto KPI snapshot from a v1 scrape.db SQLite file. ARGS: db_path=/path/to/scrape.db"
  task import_toronto_v1: :environment do
    db_path = ENV["db_path"] || ENV["DB_PATH"]
    abort "Usage: bin/rails kpis:import_toronto_v1 db_path=/abs/path/to/scrape.db" if db_path.blank?
    abort "File not found: #{db_path}" unless File.exist?(db_path)

    source = Warehouse::Source.find_or_create_by!(name: "toronto-budgets-v1-snapshot") do |s|
      s.url = "file://#{db_path}"
      s.format = "sqlite"
    end

    checksum = Digest::SHA256.file(db_path).hexdigest
    raw = Warehouse::RawIngestion.find_or_initialize_by(source: source, checksum: checksum)
    raw.assign_attributes(
      fetched_at: Time.current,
      raw_file_path: db_path,
      status: "pending"
    )
    raw.save!

    counts = raw.toronto_kpis_v1_loader.load
    puts "  documents:      #{counts[:documents]}"
    puts "  measures:       #{counts[:measures]}"
    puts "  citations:      #{counts[:citations]}"
    puts "  ratio_cleanups: #{counts[:ratio_cleanups]}"
    puts "Imported. RawIngestion #{raw.id} status: #{raw.reload.status}"
  end

  desc "Export period_basis candidate citations to CSV for human labeling"
  task :export_period_basis_candidates, [ :csv_path ] => :environment do |_, args|
    require "csv"
    csv_path = args[:csv_path] || Rails.root.join("tmp/period_basis_candidates.csv").to_s

    sql = <<~SQL
      SELECT id, measurement_year, value_type, document_id, value_numeric, notes
      FROM warehouse.measure_citations
      WHERE notes ~* '\\m(ytd|year-to-date|as of|cumulative|partial|q[1-3])\\M'
      ORDER BY id
    SQL

    rows = ActiveRecord::Base.connection.exec_query(sql).to_a
    CSV.open(csv_path, "w") do |csv|
      csv << [ "id", "measurement_year", "value_type", "document_id", "value_numeric", "notes", "period_basis_label" ]
      rows.each do |r|
        csv << [ r["id"], r["measurement_year"], r["value_type"], r["document_id"], r["value_numeric"], r["notes"], "full_year" ]
      end
    end

    puts "Exported #{rows.length} candidate citations to #{csv_path}"
    puts "Edit the period_basis_label column with one of: full_year, ytd_q1, ytd_q2, ytd_q3, as_of_date"
    puts "Then run: bin/rails kpis:apply_period_basis[#{csv_path}]"
  end

  desc "Apply period_basis labels from a labeled CSV"
  task :apply_period_basis, [ :csv_path ] => :environment do |_, args|
    require "csv"
    csv_path = args[:csv_path] || Rails.root.join("tmp/period_basis_candidates.csv").to_s
    abort "File not found: #{csv_path}" unless File.exist?(csv_path)

    updated = 0
    invalid = []
    valid = Warehouse::MeasureCitation::PERIOD_BASES

    ActiveRecord::Base.transaction do
      CSV.foreach(csv_path, headers: true) do |row|
        id = row["id"].to_i
        label = row["period_basis_label"]
        unless valid.include?(label)
          invalid << [ id, label ]
          next
        end
        Warehouse::MeasureCitation.where(id: id).update_all(period_basis: label)
        updated += 1
      end
      raise ActiveRecord::Rollback, "Invalid labels: #{invalid.inspect}" if invalid.any?
    end

    puts "Updated #{updated} citations"
  end

  desc "Issue a new KPI API token. ARGS: name=<id> [scopes=kpis:read,kpis:write]"
  task issue_token: :environment do
    name = ENV.fetch("name") { abort "Usage: bin/rails kpis:issue_token name=<id> [scopes=kpis:read,kpis:write]" }
    scopes = (ENV["scopes"] || "kpis:read,kpis:write").split(",").map(&:strip)
    raw = ::Warehouse::ApiToken.issue!(name: name, scopes: scopes)
    puts "Token (record once, not stored): #{raw}"
    puts "Scopes: #{scopes.join(', ')}"
  end

  private

  def seed_toronto_jurisdiction
    Warehouse::Jurisdiction.find_or_create_by!(code: "TOR-ON") do |j|
      j.name = "City of Toronto"
      j.slug = "toronto"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
      j.region_code = "ON"
    end
  end

  def seed_units(yaml_path)
    data = YAML.safe_load_file(yaml_path, permitted_classes: [ Symbol ], aliases: true)
    count = 0
    data.fetch("units").each do |row|
      unit = Warehouse::Unit.find_or_initialize_by(symbol: row.fetch("symbol"))
      unit.assign_attributes(
        kind: row.fetch("kind"),
        base_unit: row["base_unit"],
        scale: row.fetch("scale", 1.0),
        currency_code: row["currency_code"],
        denominator_unit: row["denominator_unit"],
        denominator_scale: row["denominator_scale"],
        notes: row["notes"]
      )
      unit.save!
      count += 1
    end
    count
  end

  def seed_toronto_organizations(yaml_path)
    data = YAML.safe_load_file(yaml_path, permitted_classes: [ Symbol ], aliases: true)
    toronto = Warehouse::Jurisdiction.find_by!(slug: "toronto")
    org_count = 0
    alias_count = 0

    data.fetch("organizations").each do |row|
      org = Warehouse::Organization.find_or_initialize_by(
        jurisdiction_id: toronto.id,
        slug: row.fetch("slug")
      )
      org.canonical_name = row.fetch("canonical_name")
      org.active_from_year = row["active_from_year"]
      org.active_to_year = row["active_to_year"]
      org.description = row["description"]
      org.kind = row["kind"]
      org.save!
      org_count += 1

      Array(row["aliases"]).each do |alias_name|
        next if org.organization_aliases.exists?(alias_name: alias_name)
        org.organization_aliases.create!(alias_name: alias_name)
        alias_count += 1
      end

      # Also register the canonical name as an alias for lookup.
      unless org.organization_aliases.exists?(alias_name: org.canonical_name)
        org.organization_aliases.create!(alias_name: org.canonical_name)
        alias_count += 1
      end
    end

    [ org_count, alias_count ]
  end

  def seed_toronto_organization_lineages(yaml_path)
    data = YAML.safe_load_file(yaml_path, permitted_classes: [ Symbol ], aliases: true)
    toronto = Warehouse::Jurisdiction.find_by!(slug: "toronto")
    count = 0

    data.fetch("lineages").each do |row|
      pred = Warehouse::Organization.find_by!(jurisdiction_id: toronto.id, slug: row.fetch("predecessor"))
      succ = Warehouse::Organization.find_by!(jurisdiction_id: toronto.id, slug: row.fetch("successor"))

      Warehouse::OrganizationLineage.find_or_create_by!(
        predecessor_id: pred.id,
        successor_id: succ.id,
        transition_year: row.fetch("year"),
        transition_kind: row.fetch("kind")
      ) do |lineage|
        lineage.notes = row["notes"]
      end
      count += 1
    end

    count
  end
end
