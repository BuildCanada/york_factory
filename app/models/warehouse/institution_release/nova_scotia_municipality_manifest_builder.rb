require "date"
require "digest"
require "json"
require "pathname"
require "set"
require "time"
require "uri"

class Warehouse::InstitutionRelease::NovaScotiaMunicipalityManifestBuilder
  class BuildError < StandardError; end

  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")

  attr_reader :warnings

  def initialize(base_path:, batch_paths:, output_path:, release_version:, effective_on: release_version,
    published_at: "#{release_version}T00:00:00Z", source_retrieved_at: nil,
    previous_path: nil, asset_root: DEFAULT_ASSET_ROOT, verify_assets: true)
    @base_path = Pathname(base_path)
    @batch_paths = batch_paths.map { |path| Pathname(path) }
    @output_path = Pathname(output_path)
    @release_version = release_version
    @effective_on = effective_on
    @published_at = published_at
    @source_retrieved_at = source_retrieved_at
    @previous_path = Pathname(previous_path) if previous_path
    @asset_root = Pathname(asset_root).expand_path
    @verify_assets = verify_assets
    @warnings = []
  end

  def call
    validate_release_metadata!
    base = read_json(@base_path)
    validate_unique_canonical_ids!(base.fetch("municipalities"))
    municipalities = base.fetch("municipalities").to_h do |row|
      normalized = stringify_keys(row)
      [ normalized.fetch("canonical_id"), normalized ]
    end
    audit = { "batches" => [], "municipalities" => {} }

    @batch_paths.each do |batch_path|
      batch = read_json(batch_path)
      batch_retrieved_at = required_time(batch["retrieved_at"], "#{batch_path} retrieved_at")
      audit["batches"] << input_file_record(batch_path).merge(
        "batch" => batch["batch"] || batch_path.basename.to_s,
        "retrieved_at" => batch_retrieved_at.iso8601
      )

      batch.fetch("municipalities").each do |incoming|
        incoming = stringify_keys(incoming)
        canonical_id = incoming.fetch("canonical_id")
        municipality = municipalities.fetch(canonical_id) do
          raise BuildError, "unknown municipality #{canonical_id} in #{batch_path}"
        end
        %w[financial_statements annual_reports].each do |key|
          municipality[key] = merge_exact_documents(
            Array(municipality[key]),
            Array(incoming[key]),
            fallback_retrieved_at: batch_retrieved_at
          )
        end
        append_audit!(audit, canonical_id, batch_path, incoming)
      end
    end

    source_retrieved_at = @source_retrieved_at || base["source_retrieved_at"] ||
      "#{base.fetch('release_version')}T00:00:00Z"
    required_time(source_retrieved_at, "source_retrieved_at")
    province = base["province"] || {
      "code" => "ns",
      "statcan_code" => "12",
      "name_en" => "Nova Scotia",
      "name_fr" => "Nouvelle-Écosse",
      "government_name_en" => "Government of Nova Scotia",
      "government_name_fr" => "Gouvernement de la Nouvelle-Écosse",
      "website_url" => "https://www.novascotia.ca/",
      "source_languages" => [ "en", "fr" ],
      "source_license" => "Open Government Licence - Nova Scotia"
    }

    municipalities.each_value do |municipality|
      raw_documents = Array(municipality.delete("financial_statements")) +
        Array(municipality.delete("annual_reports"))
      municipality["documents"] = build_document_works(
        municipality.fetch("canonical_id"),
        raw_documents,
        fallback_retrieved_at: required_time(source_retrieved_at, "source_retrieved_at")
      )
    end

    output = {
      "product" => "canadian-public-institutions",
      "release_version" => @release_version,
      "effective_on" => @effective_on,
      "schema_version" => "1.0",
      "published_at" => required_time(@published_at, "published_at").iso8601,
      "source_retrieved_at" => required_time(source_retrieved_at, "source_retrieved_at").iso8601,
      "geography_vintage" => Integer(base.fetch("geography_vintage")),
      "attribution" => base["attribution"] ||
        "Contains information from official municipal, #{province.fetch('name_en')}, and Statistics Canada sources; rights and attribution are recorded per source.",
      "province" => province,
      "roster_source_url" => base.fetch("roster_source_url"),
      "roster_source_title" => base["roster_source_title"],
      "roster_source_publisher" => base["roster_source_publisher"],
      "geography_source_url" => base.fetch("geography_source_url"),
      "raw_input_files" => [ input_file_record(@base_path), *@batch_paths.map { |path| input_file_record(path) } ],
      "scrape_audit" => audit,
      "municipalities" => municipalities.values.sort_by { |row| row.fetch("canonical_id") },
      "relationships" => Array(base["relationships"]).map { |row| stringify_keys(row) }.sort_by do |row|
        [ row.fetch("source_id"), row.fetch("relationship_type"), row.fetch("target_id"), row["valid_from"].to_s ]
      end
    }

    validate_previous_release!(output)
    validate_output!(output)
    @output_path.dirname.mkpath
    @output_path.write(JSON.pretty_generate(output) << "\n")
    output
  rescue Errno::ENOENT, JSON::ParserError, KeyError, Date::Error, ArgumentError => error
    raise BuildError, error.message
  end

  private

  def validate_unique_canonical_ids!(rows)
    duplicates = rows.map { |row| row.fetch("canonical_id") }.tally
      .select { |_canonical_id, count| count > 1 }.keys
    return if duplicates.empty?

    raise BuildError, "base manifest has duplicate canonical IDs: #{duplicates.join(', ')}"
  end

  def validate_release_metadata!
    release_date = Date.iso8601(@release_version)
    effective_date = Date.iso8601(@effective_on)
    raise BuildError, "release version and effective date must match" unless release_date == effective_date

    required_time(@published_at, "published_at")
    if @output_path.exist?
      raise BuildError, "refusing to overwrite existing release manifest: #{@output_path}"
    end
  end

  def read_json(path)
    payload = JSON.parse(path.read)
    raise BuildError, "#{path} must contain a JSON object" unless payload.is_a?(Hash)

    stringify_keys(payload)
  end

  def stringify_keys(value)
    case value
    when Hash
      value.to_h { |key, child| [ key.to_s, stringify_keys(child) ] }
    when Array
      value.map { |child| stringify_keys(child) }
    else
      value
    end
  end

  def merge_exact_documents(existing, incoming, fallback_retrieved_at:)
    documents = (existing + incoming).map do |document|
      normalize_document(document, fallback_retrieved_at: fallback_retrieved_at)
    end
    merged = []

    documents.sort_by { |document| document_quality(document) }.reverse_each do |document|
      duplicate = merged.find { |candidate| exact_duplicate?(candidate, document) }
      if duplicate
        merge_missing!(duplicate, document)
      else
        merged << document
      end
    end

    merged.sort_by { |document| document_sort_key(document) }
  end

  def normalize_document(document, fallback_retrieved_at:)
    normalized = stringify_keys(document)
    normalized["document_type"] = normalize_document_type(normalized["document_type"] || "financial_statements")
    normalized["rights_status"] ||= "metadata_only"
    normalized["languages"] = Array(normalized["languages"])
    normalized["languages"] = [ "en" ] if normalized["languages"].empty?
    normalized["retrieved_at"] = required_time(
      normalized["retrieved_at"] || fallback_retrieved_at,
      "document retrieved_at"
    ).iso8601
    normalized
  end

  def exact_duplicate?(left, right)
    same_present_value?(left, right, "content_sha256") ||
      same_normalized_url?(left["download_url"], right["download_url"])
  end

  def same_normalized_url?(left, right)
    left = normalized_url(left)
    right = normalized_url(right)
    left && left == right
  end

  def normalized_url(value)
    return if value.to_s.empty?

    uri = URI(value)
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    value
  end

  def merge_missing!(target, source)
    source.each do |key, value|
      target[key] = value if !value_present?(target[key]) && value_present?(value)
    end
    target
  end

  def document_quality(document)
    score = 0
    score += 100 if value_present?(document["archive_path"])
    score += 20 if value_present?(document["fiscal_period_end"])
    score += 10 if value_present?(document["fiscal_period_start"])
    score += 5 if value_present?(document["source_page_url"])
    score += asset_role_score(asset_role(document))
    score
  end

  def build_document_works(institution_id, raw_documents, fallback_retrieved_at:)
    documents = raw_documents.map do |document|
      normalize_document(document, fallback_retrieved_at: fallback_retrieved_at)
    end
    documents = merge_exact_documents([], documents, fallback_retrieved_at: fallback_retrieved_at)

    documents.group_by do |document|
      [ document.fetch("document_type"), statement_year(document), document_variant(document) ]
    end.map do |(type, year, variant), records|
      build_document_work(institution_id, type, year, variant, records)
    end.sort_by { |document| document.fetch("canonical_id") }
  end

  def build_document_work(institution_id, type, year, variant, records)
    preferred_record = records.max_by { |record| document_quality(record) }
    assets = records.filter_map { |record| build_asset(record) }
      .uniq { |asset| asset.fetch("content_sha256") }
    assign_part_counts!(assets)
    assign_preferred_asset!(assets)

    notes = records.flat_map do |record|
      [ record["notes"], *Array(record["evidence"]) ]
    end.compact.map(&:to_s).reject(&:empty?).uniq

    {
      "canonical_id" => "#{institution_id}/documents/#{type}/#{year}/#{variant}",
      "document_type" => type,
      "document_variant" => variant,
      "title" => preferred_record["title"],
      "title_fr" => preferred_record["title_fr"],
      "fiscal_period_start" => preferred_record["fiscal_period_start"],
      "fiscal_period_end" => preferred_record["fiscal_period_end"],
      "published_on" => records.filter_map { |record| record["published_on"] }.max,
      "source_page_url" => records.filter_map { |record| record["source_page_url"] }.first,
      "download_url" => preferred_record["download_url"],
      "notes" => notes.empty? ? nil : notes.join(" | "),
      "assets" => assets.sort_by { |asset| [ asset.fetch("asset_role"), asset["part_index"].to_i, asset.fetch("content_sha256") ] }
    }.compact
  end

  def build_asset(record)
    return unless value_present?(record["content_sha256"]) && value_present?(record["archive_path"])

    role, part_index = asset_role_and_part(record)
    {
      "content_sha256" => record.fetch("content_sha256"),
      "asset_role" => role,
      "part_index" => part_index,
      "preferred" => false,
      "download_url" => record["download_url"] || record.fetch("source_page_url"),
      "retrieved_at" => required_time(record.fetch("retrieved_at"), "asset retrieved_at").iso8601,
      "archive_path" => record.fetch("archive_path"),
      "mime_type" => record["mime_type"] || "application/pdf",
      "byte_size" => Integer(record.fetch("byte_size")),
      "rights_status" => record.fetch("rights_status", "metadata_only"),
      "page_locator" => record["page_locator"]
    }.compact
  end

  def assign_part_counts!(assets)
    parts = assets.select { |asset| asset["asset_role"] == "part" }
    return if parts.empty?

    count = parts.filter_map { |asset| asset["part_index"] }.max
    parts.each { |asset| asset["part_count"] = count }
  end

  def assign_preferred_asset!(assets)
    candidates = assets.reject { |asset| %w[part container draft].include?(asset["asset_role"]) }
    preferred = candidates.max_by do |asset|
      [ asset_role_score(asset["asset_role"]), asset.fetch("retrieved_at"), asset.fetch("content_sha256") ]
    end
    preferred["preferred"] = true if preferred
  end

  def asset_role(document)
    asset_role_and_part(document).first
  end

  def asset_role_and_part(document)
    text = [ document["title"], document["notes"], *Array(document["evidence"]) ].compact.join(" ").downcase
    part_match = text.match(/\bpart[\s_-]*(\d+)\b/)
    return [ "part", Integer(part_match[1]) ] if part_match
    return [ "container", nil ] if text.match?(/\b(agenda|minutes|meeting package)\b/)
    return [ "draft", nil ] if text.include?("draft")
    return [ "amended", nil ] if text.match?(/\b(amended|revised|restated)\b/)
    return [ "final", nil ] if text.match?(/\b(final|signed|audited|audit|financial statements)\b/)

    [ "unknown", nil ]
  end

  def asset_role_score(role)
    { "amended" => 50, "final" => 40, "unknown" => 30, "part" => 20, "container" => 10, "draft" => 0 }.fetch(role, 0)
  end

  def document_variant(document)
    explicit = document["document_variant"].to_s.tr("_", "-")
    return explicit unless explicit.empty?

    title = document["title"].to_s.downcase
    return "non-consolidated" if title.match?(/non.?consolidated/)
    return "compiled" if title.include?("compiled")
    return "trust-funds" if title.include?("trust fund")
    return "consolidated" if title.include?("consolidated")

    "general"
  end

  def normalize_document_type(value)
    value.to_s.tr("_", "-")
  end

  def statement_year(document)
    date = document["fiscal_period_end"] || document["published_on"]
    if date.to_s.empty?
      title_year = document["title"].to_s.scan(/\b20\d{2}\b/).last
      return Integer(title_year) if title_year

      raise BuildError, "document has no fiscal period end, publication date, or title year: #{document.inspect}"
    end

    Date.iso8601(date).year
  end

  def document_sort_key(document)
    [ document["fiscal_period_end"].to_s, document["published_on"].to_s, document["title"].to_s ]
  end

  def append_audit!(audit, canonical_id, batch_path, incoming)
    audit["municipalities"][canonical_id] ||= []
    audit["municipalities"][canonical_id] << {
      "batch" => batch_path.basename.to_s,
      "searched_locations" => Array(incoming["searched_locations"]).uniq.sort,
      "gaps" => Array(incoming["gaps"]).uniq.sort
    }
  end

  def input_file_record(path)
    {
      "name" => path.basename.to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "byte_size" => path.size
    }
  end

  def validate_previous_release!(output)
    return unless @previous_path

    previous = read_json(@previous_path)
    previous_rows = previous.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    current_rows = output.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }

    (previous_rows.keys - current_rows.keys).sort.each do |canonical_id|
      warnings << "institution disappeared since previous release: #{canonical_id}"
    end
    (previous_rows.keys & current_rows.keys).each do |canonical_id|
      previous_type = [ previous_rows[canonical_id]["municipality_type"], previous_rows[canonical_id]["government_level"] ]
      current_type = [ current_rows[canonical_id]["municipality_type"], current_rows[canonical_id]["government_level"] ]
      next if previous_type == current_type

      raise BuildError, "canonical institution ID changed meaning: #{canonical_id}"
    end


    previous_identifiers = identifier_owners(previous_rows.values)
    current_identifiers = identifier_owners(current_rows.values)
    (previous_identifiers.keys & current_identifiers.keys).each do |identifier|
      next if previous_identifiers[identifier] == current_identifiers[identifier]

      raise BuildError,
        "identifier #{identifier.join('=')} moved from #{previous_identifiers[identifier]} to #{current_identifiers[identifier]}"
    end
  end

  def identifier_owners(rows)
    rows.each_with_object({}) do |row, owners|
      Array(row["identifiers"]).each do |identifier|
        next if identifier["scheme"].to_s.empty? || identifier["value"].to_s.empty?

        owners[[ identifier.fetch("scheme"), identifier.fetch("value").to_s ]] = row.fetch("canonical_id")
      end
    end
  end

  def validate_output!(output)
    ids = output.fetch("municipalities").map { |row| row.fetch("canonical_id") }
    duplicates = ids.tally.select { |_id, count| count > 1 }.keys
    raise BuildError, "duplicate institution IDs: #{duplicates.join(', ')}" if duplicates.any?

    document_ids = []
    output.fetch("municipalities").each do |municipality|
      municipality.fetch("documents").each do |document|
        document_ids << document.fetch("canonical_id")
        if document["source_page_url"].to_s.empty? && document["download_url"].to_s.empty?
          raise BuildError, "#{document.fetch('canonical_id')} has no source evidence"
        end
        document.fetch("assets").each { |asset| validate_asset!(document.fetch("canonical_id"), asset) }
      end
    end
    duplicate_documents = document_ids.tally.select { |_id, count| count > 1 }.keys
    raise BuildError, "duplicate document IDs: #{duplicate_documents.join(', ')}" if duplicate_documents.any?

    institution_ids = ids.to_set << "ca/#{output.fetch('province').fetch('code')}"
    relationship_keys = output.fetch("relationships").map do |relationship|
      source_id = relationship.fetch("source_id")
      target_id = relationship.fetch("target_id")
      type = relationship.fetch("relationship_type")
      raise BuildError, "relationship source is absent: #{source_id}" unless institution_ids.include?(source_id)
      raise BuildError, "relationship target is absent: #{target_id}" unless institution_ids.include?(target_id)
      raise BuildError, "relationship cannot be reflexive: #{source_id}" if source_id == target_id

      [ source_id, target_id, type, relationship["valid_from"] ]
    end
    duplicate_relationships = relationship_keys.tally.select { |_key, count| count > 1 }.keys
    if duplicate_relationships.any?
      raise BuildError, "duplicate relationships: #{duplicate_relationships.map { |key| key.join('/') }.join(', ')}"
    end
  end

  def validate_asset!(document_id, asset)
    hash = asset.fetch("content_sha256")
    raise BuildError, "invalid SHA-256 for #{document_id}" unless hash.match?(/\A[0-9a-f]{64}\z/)
    return unless @verify_assets

    candidate = @asset_root.join(asset.fetch("archive_path")).expand_path
    root_prefix = "#{@asset_root.to_s.delete_suffix(File::SEPARATOR)}#{File::SEPARATOR}"
    raise BuildError, "archive escapes asset root: #{candidate}" unless candidate.to_s.start_with?(root_prefix)
    raise BuildError, "missing archive for #{document_id}: #{candidate}" unless candidate.file?
    raise BuildError, "archive hash mismatch for #{document_id}: #{candidate}" unless Digest::SHA256.file(candidate).hexdigest == hash
    raise BuildError, "archive size mismatch for #{document_id}: #{candidate}" unless candidate.size == Integer(asset.fetch("byte_size"))
    raise BuildError, "archive MIME must be application/pdf for #{document_id}" unless asset.fetch("mime_type") == "application/pdf"
    raise BuildError, "archive is not a PDF for #{document_id}: #{candidate}" unless candidate.binread(5) == "%PDF-"
  end

  def value_present?(value)
    !(value.nil? || value == "" || value == [])
  end

  def same_present_value?(left, right, key)
    value_present?(left[key]) && left[key] == right[key]
  end

  def required_time(value, label)
    value.is_a?(Time) ? value : Time.iso8601(value.to_s)
  rescue ArgumentError
    raise BuildError, "invalid #{label}: #{value.inspect}"
  end
end
