namespace :kpis do
  desc "Seed KPI reference data (jurisdictions, units, organizations, lineages) from db/seeds/kpis/*.yml"
  task seed_reference: :environment do
    require "yaml"

    seed_dir = Rails.root.join("db/seeds/kpis")

    ActiveRecord::Base.transaction do
      seed_toronto_jurisdiction
      units_seeded = seed_units(seed_dir.join("units.yml"))
      tor_orgs, tor_aliases = seed_organizations_for(
        jurisdiction_code: "TOR-ON",
        path: seed_dir.join("toronto_organizations.yml")
      )
      fed_orgs, fed_aliases = seed_organizations_for(
        jurisdiction_code: "CA",
        path: seed_dir.join("federal_organizations.yml")
      )
      lineages_seeded = seed_toronto_organization_lineages(seed_dir.join("toronto_organization_lineages.yml"))
      countries_seeded = seed_countries(seed_dir.join("countries.yml"))
      measure_counts = Dir.glob(seed_dir.join("*_measures.yml")).sort.to_h do |path|
        [ File.basename(path, ".yml"), seed_economy_measures(path) ]
      end

      puts "Seeded:"
      puts "  units:                  #{units_seeded}"
      puts "  toronto organizations:  #{tor_orgs}  (aliases: #{tor_aliases})"
      puts "  federal organizations:  #{fed_orgs}  (aliases: #{fed_aliases})"
      puts "  organization_lineages:  #{lineages_seeded}"
      puts "  countries:              #{countries_seeded}"
      measure_counts.each do |name, count|
        puts "  #{name.ljust(22)} #{count}"
      end
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
    puts "Imported. RawIngestion #{raw.id} status: #{raw.reload.status}"
  end

  desc "Seed frozen historical PR admissions (total + by class, 1980-2015) from IRCC's archived by-category dataset."
  task seed_pr_admissions_historical: :environment do
    # Grand-total and class-subtotal rows of IRCC's "Admissions of Permanent
    # Residents by Immigration Category, 1980-Q2 2016" (IRCC_PRadmiss_0002_E.xls).
    # Frozen — the dataset is archived and will not update. 2016 is excluded
    # (Q1-Q2 only). The frontend splices each with the live monthly series for
    # 2015+.
    series = {
      "pr-admissions-annual-historical" => {
        1980 => 143138, 1981 => 128641, 1982 => 121178, 1983 => 89185,
        1984 => 88272, 1985 => 84347, 1986 => 99352, 1987 => 152077,
        1988 => 161585, 1989 => 191550, 1990 => 216451, 1991 => 232790,
        1992 => 254787, 1993 => 256637, 1994 => 224382, 1995 => 212862,
        1996 => 226071, 1997 => 216036, 1998 => 174195, 1999 => 189950,
        2000 => 227470, 2001 => 250656, 2002 => 229123, 2003 => 221396,
        2004 => 235858, 2005 => 262246, 2006 => 251649, 2007 => 236762,
        2008 => 247261, 2009 => 252218, 2010 => 280730, 2011 => 248732,
        2012 => 257809, 2013 => 259039, 2014 => 260282, 2015 => 271847
      },
      "pr-admissions-economic-historical" => {
        1980 => 49891, 1981 => 60238, 1982 => 51706, 1983 => 24185,
        1984 => 26078, 1985 => 26112, 1986 => 35837, 1987 => 74101,
        1988 => 80219, 1989 => 90143, 1990 => 97929, 1991 => 86499,
        1992 => 95789, 1993 => 105651, 1994 => 102307, 1995 => 106624,
        1996 => 125368, 1997 => 128349, 1998 => 97909, 1999 => 109247,
        2000 => 136292, 2001 => 155716, 2002 => 138503, 2003 => 122738,
        2004 => 134308, 2005 => 156370, 2006 => 138338, 2007 => 131271,
        2008 => 149111, 2009 => 153548, 2010 => 186968, 2011 => 156120,
        2012 => 160790, 2013 => 148254, 2014 => 165188, 2015 => 170398
      },
      "pr-admissions-family-historical" => {
        1980 => 51353, 1981 => 51360, 1982 => 50287, 1983 => 48938,
        1984 => 44520, 1985 => 39362, 1986 => 42476, 1987 => 53839,
        1988 => 51429, 1989 => 60969, 1990 => 74684, 1991 => 87956,
        1992 => 101110, 1993 => 112644, 1994 => 94188, 1995 => 77384,
        1996 => 68360, 1997 => 59979, 1998 => 50896, 1999 => 55274,
        2000 => 60623, 2001 => 66814, 2002 => 65338, 2003 => 70732,
        2004 => 63554, 2005 => 64008, 2006 => 71288, 2007 => 67081,
        2008 => 66422, 2009 => 66064, 2010 => 60743, 2011 => 56990,
        2012 => 65502, 2013 => 83379, 2014 => 67647, 2015 => 65490
      },
      "pr-admissions-refugee-historical" => {
        1980 => 40344, 1981 => 14980, 1982 => 16933, 1983 => 13968,
        1984 => 15360, 1985 => 16772, 1986 => 19204, 1987 => 21471,
        1988 => 26766, 1989 => 36869, 1990 => 40237, 1991 => 54087,
        1992 => 52344, 1993 => 30591, 1994 => 20433, 1995 => 28093,
        1996 => 28477, 1997 => 24308, 1998 => 22843, 1999 => 24398,
        2000 => 30095, 2001 => 27919, 2002 => 25118, 2003 => 25993,
        2004 => 32695, 2005 => 35776, 2006 => 32501, 2007 => 27955,
        2008 => 21860, 2009 => 22855, 2010 => 24699, 2011 => 27873,
        2012 => 23092, 2013 => 24129, 2014 => 24068, 2015 => 32111
      },
      "pr-admissions-other-historical" => {
        1980 => 1548, 1981 => 2063, 1982 => 2252, 1983 => 2094,
        1984 => 2314, 1985 => 2101, 1986 => 1835, 1987 => 2666,
        1988 => 3171, 1989 => 3567, 1990 => 3601, 1991 => 4248,
        1992 => 5544, 1993 => 7751, 1994 => 7453, 1995 => 761,
        1996 => 3865, 1997 => 3400, 1998 => 2547, 1999 => 1031,
        2000 => 460, 2001 => 206, 2002 => 164, 2003 => 1933,
        2004 => 5301, 2005 => 6092, 2006 => 9522, 2007 => 10455,
        2008 => 9868, 2009 => 9751, 2010 => 8320, 2011 => 7749,
        2012 => 8425, 2013 => 3277, 2014 => 3379, 2015 => 3848
      }
    }

    source = Warehouse::Source.find_or_create_by!(name: "ircc_pr_admissions_historical") do |s|
      s.url = "https://www.ircc.canada.ca/opendata-donneesouvertes/data/IRCC_PRadmiss_0002_E.xls"
      s.format = "xls_static"
      s.fetch_frequency = "manual"
    end
    source.update!(
      license: "Open Government Licence - Canada",
      attribution: "Immigration, Refugees and Citizenship Canada, Admissions of Permanent Residents by Immigration Category (1980-Q2 2016), Open Government Licence - Canada"
    )

    raw = Warehouse::RawIngestion.find_or_initialize_by(
      source: source, checksum: "pr-admiss-hist-1980-2015-v2-byclass"
    )
    raw.assign_attributes(
      fetched_at: Time.current,
      raw_file_path: "IRCC_PRadmiss_0002_E.xls",
      status: "pending"
    )
    raw.save!

    tuples = series.flat_map do |slug, by_year|
      by_year.map do |year, value|
        {
          measure_slug: slug,
          country_code: "CAN",
          year: year.to_s,
          period: year.to_s,
          value: value
        }
      end
    end

    counts = Warehouse::Economy::ObservationWriter.new(raw_ingestion: raw).write(tuples)
    raw.update!(status: "complete")
    puts "Seeded historical PR admissions (#{series.keys.size} series): #{counts.inspect}"
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

  desc "Classify period_basis on candidate citations using an LLM. Writes a CSV audit trail."
  task :classify_period_basis, [ :audit_csv_path ] => :environment do |_, args|
    require "csv"
    audit_path = args[:audit_csv_path] || Rails.root.join("tmp/period_basis_classifications_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv").to_s

    # Same candidate set as the export task. Excludes rows already labeled (non-default).
    candidates = Warehouse::MeasureCitation
      .where("notes ~* ?", '\m(ytd|year-to-date|as of|cumulative|partial|q[1-3])\M')
      .where(period_basis: "full_year")
      .includes(:measure)
      .order(:id)

    total = candidates.count
    if total.zero?
      puts "No candidate citations to classify."
      next
    end

    puts "Classifying #{total} citations with #{Warehouse::MeasureCitation::PeriodBasisClassifier::LLM_MODEL}..."

    audited = []
    updated = 0
    skipped_low_confidence = 0

    Warehouse::MeasureCitation::PeriodBasisClassifier.classify_batch(candidates.to_a) do |citation, result|
      audited << {
        id: citation.id,
        measurement_year: citation.measurement_year,
        value_type: citation.value_type,
        notes: citation.notes,
        proposed_label: result.period_basis,
        confidence: result.confidence,
        reasoning: result.reasoning,
        applied: false
      }

      if result.period_basis.nil? || result.confidence < Warehouse::MeasureCitation::PeriodBasisClassifier::AUTO_ACCEPT_CONFIDENCE
        skipped_low_confidence += 1
        next
      end

      next if result.period_basis == citation.period_basis

      citation.update_columns(period_basis: result.period_basis)
      audited.last[:applied] = true
      updated += 1
    end

    CSV.open(audit_path, "w") do |csv|
      csv << %w[id measurement_year value_type notes proposed_label confidence reasoning applied]
      audited.each { |r| csv << r.values_at(:id, :measurement_year, :value_type, :notes, :proposed_label, :confidence, :reasoning, :applied) }
    end

    puts "Updated:                #{updated}"
    puts "Skipped (low confidence or no label): #{skipped_low_confidence}"
    puts "Audit CSV:              #{audit_path}"
    puts "Review skipped rows in the CSV; re-apply by editing applied=true and running kpis:apply_period_basis_from_audit"
  end

  desc "Apply period_basis labels from an audit CSV (rows with applied=true and a proposed_label)"
  task :apply_period_basis_from_audit, [ :csv_path ] => :environment do |_, args|
    require "csv"
    csv_path = args[:csv_path] || abort("Usage: bin/rails kpis:apply_period_basis_from_audit[/path/to/audit.csv]")
    abort "File not found: #{csv_path}" unless File.exist?(csv_path)

    valid = Warehouse::MeasureCitation::PERIOD_BASES
    updated = 0
    invalid = []

    ActiveRecord::Base.transaction do
      CSV.foreach(csv_path, headers: true) do |row|
        next unless ActiveModel::Type::Boolean.new.cast(row["applied"])
        label = row["proposed_label"]
        unless valid.include?(label)
          invalid << [ row["id"], label ]
          next
        end
        Warehouse::MeasureCitation.where(id: row["id"].to_i).update_all(period_basis: label)
        updated += 1
      end
      raise ActiveRecord::Rollback, "Invalid labels: #{invalid.inspect}" if invalid.any?
    end

    puts "Updated #{updated} citations from audit CSV"
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

  desc "Backfill citations stored in BASE_UNIT form back to DISPLAY form. Scoped to a raw_ingestion source name (default: toronto-budgets-v1-snapshot)."
  task :rescale_to_display, [ :source_name ] => :environment do |_, args|
    source_name = args[:source_name] || "toronto-budgets-v1-snapshot"
    source = Warehouse::Source.find_by(name: source_name)
    abort "Source not found: #{source_name}" if source.nil?

    sql_audit = <<~SQL
      SELECT u.symbol, u.scale, COUNT(*) AS rows
      FROM warehouse.measure_citations c
      JOIN warehouse.measures m       ON m.id = c.measure_id
      JOIN warehouse.units u          ON u.id = m.unit_id
      JOIN warehouse.kpi_documents d  ON d.id = c.document_id
      JOIN warehouse.raw_ingestions ri ON ri.id = d.raw_ingestion_id
      WHERE ri.source_id = #{source.id}
        AND u.scale <> 1.0
        AND c.value_numeric IS NOT NULL
      GROUP BY u.symbol, u.scale
      ORDER BY rows DESC
    SQL
    puts "About to rescale (divide value_numeric by unit.scale):"
    total = 0
    ActiveRecord::Base.connection.exec_query(sql_audit).each do |r|
      total += r["rows"].to_i
      puts "  %-22s scale=%-14s rows=%d" % [ r["symbol"], r["scale"], r["rows"] ]
    end
    puts "Total rows: #{total}"

    if total.zero?
      puts "Nothing to do."
      next
    end

    sql_update = <<~SQL
      UPDATE warehouse.measure_citations AS c
      SET value_numeric = c.value_numeric / u.scale,
          updated_at = NOW(),
          notes = CASE
            WHEN c.notes IS NULL OR c.notes = '' THEN '[rescaled to display units]'
            ELSE c.notes || ' [rescaled to display units]'
          END
      FROM warehouse.measures m, warehouse.units u, warehouse.kpi_documents d, warehouse.raw_ingestions ri
      WHERE c.measure_id = m.id
        AND m.unit_id = u.id
        AND c.document_id = d.id
        AND d.raw_ingestion_id = ri.id
        AND ri.source_id = #{source.id}
        AND u.scale <> 1.0
        AND c.value_numeric IS NOT NULL
    SQL

    result = ActiveRecord::Base.connection.execute(sql_update)
    puts "Rescaled #{result.cmd_tuples} rows."
  end

  desc "Normalize service_category by stripping trailing parenthetical quality tags from existing measures."
  task normalize_service_categories: :environment do
    affected = 0
    Warehouse::Measure.where.not(service_category: nil).find_each do |m|
      cleaned = Warehouse::Measure.normalize_service_category(m.service_category)
      next if cleaned == m.service_category
      m.update_columns(service_category: cleaned)
      affected += 1
    end
    puts "Normalized #{affected} measures."
  end

  desc "Strip the audit-noise '[rescaled to display units]' tag from citation notes (run once after kpis:rescale_to_display)."
  task strip_rescaled_notes: :environment do
    sql_count = "SELECT COUNT(*) AS n FROM warehouse.measure_citations WHERE notes LIKE '%[rescaled to display units]%'"
    before = ActiveRecord::Base.connection.exec_query(sql_count).first["n"].to_i
    puts "Citations with rescaled note: #{before}"

    sql_update = <<~SQL
      UPDATE warehouse.measure_citations
      SET notes = NULLIF(
            TRIM(REGEXP_REPLACE(notes, '\\s*\\[rescaled to display units\\]', '', 'g')),
            ''
          ),
          updated_at = NOW()
      WHERE notes LIKE '%[rescaled to display units]%'
    SQL
    result = ActiveRecord::Base.connection.execute(sql_update)
    puts "Stripped tag from #{result.cmd_tuples} citations."
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

  def seed_countries(yaml_path)
    return 0 unless File.exist?(yaml_path)
    data = YAML.safe_load_file(yaml_path, permitted_classes: [ Symbol ], aliases: true)
    count = 0

    data.fetch("countries").each do |row|
      jurisdiction = Warehouse::Jurisdiction.find_or_initialize_by(code: row.fetch("code"))
      jurisdiction.name = row.fetch("name")
      jurisdiction.level = row.fetch("level")
      jurisdiction.slug ||= row.fetch("slug")
      jurisdiction.fiscal_year_start_month ||= 1
      jurisdiction.default_currency ||= row.fetch("default_currency")
      jurisdiction.save!
      count += 1
    end

    count
  end

  def seed_economy_measures(yaml_path)
    return 0 unless File.exist?(yaml_path)
    data = YAML.safe_load_file(yaml_path, permitted_classes: [ Symbol ], aliases: true)
    count = 0

    data.fetch("measures").each do |row|
      unit = Warehouse::Unit.find_by!(symbol: row.fetch("unit"))
      measure = Warehouse::Measure.find_or_initialize_by(organization_id: nil, slug: row.fetch("slug"))
      measure.assign_attributes(
        canonical_name: row.fetch("canonical_name"),
        unit_id: unit.id,
        category: row.fetch("category"),
        frequency: row.fetch("frequency"),
        aggregation_type: row.fetch("aggregation_type"),
        higher_is_bad: row.fetch("higher_is_bad", false),
        description: row["description"]
      )
      measure.save!
      count += 1
    end

    count
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

  def seed_organizations_for(jurisdiction_code:, path:)
    return [ 0, 0 ] unless File.exist?(path)
    data = YAML.safe_load_file(path, permitted_classes: [ Symbol ], aliases: true)
    jurisdiction = Warehouse::Jurisdiction.find_by!(code: jurisdiction_code)
    org_count = 0
    alias_count = 0

    data.fetch("organizations").each do |row|
      org = Warehouse::Organization.find_or_initialize_by(
        jurisdiction_id: jurisdiction.id,
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
