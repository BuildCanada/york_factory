class Warehouse::InstitutionRelease::CombinedMunicipalityImporter <
  Warehouse::InstitutionRelease::MunicipalityImporter
  def initialize(paths:, version: nil, effective_on: nil, asset_root: DEFAULT_ASSET_ROOT, verify_assets: true)
    paths = paths.map { |path| Pathname(path) }
    raise ArgumentError, "at least one jurisdiction manifest is required" if paths.empty?

    @paths = paths
    super(path: paths.first, version: version, effective_on: effective_on,
      asset_root: asset_root, verify_assets: verify_assets)
  end

  def import!
    payloads = @paths.map { |path| JSON.parse(path.read) }
    validate_common_release!(payloads)
    payloads.zip(@paths).each do |payload, path|
      @province_metadata = nil
      @path = path
      validate_release_metadata!(payload)
      validate_rows!(payload.fetch("municipalities"))
    end

    Warehouse::Record.transaction do
      @release = create_release!(payloads.first)
      payloads.each do |payload|
        @province_metadata = nil
        sources = create_release_sources!(payload)
        import_province!(payload, sources) if include_jurisdiction_institution?(payload)
        payload.fetch("municipalities").each { |row| import_municipality!(row, payload, sources) }
      end
      payloads.zip(@paths).each do |payload, path|
        @province_metadata = nil
        @path = path
        sources = release.institution_sources.index_by(&:canonical_id)
        roster_source = sources.fetch("ca/sources/#{payload.fetch('province').fetch('code')}/institution-roster/#{payload.fetch('release_version')}")
        import_relationships!(payload, roster_source)
        import_coverage!(payload, roster_source)
      end
      validate_previous_release!
      release.validate_complete!
    end

    release
  rescue Errno::ENOENT, JSON::ParserError, KeyError, Date::Error, ArgumentError,
    ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    raise ImportError, error.message
  end

  private

  def validate_common_release!(payloads)
    keys = %w[release_version effective_on schema_version published_at geography_vintage]
    keys.each do |key|
      values = payloads.map { |payload| payload.fetch(key) }.uniq
      raise ImportError, "jurisdiction manifests disagree on #{key}: #{values.join(', ')}" unless values.one?
    end

    codes = payloads.map { |payload| payload.fetch("province").fetch("code") }
    duplicates = codes.tally.select { |_code, count| count > 1 }.keys
    raise ImportError, "duplicate province manifests: #{duplicates.join(', ')}" if duplicates.any?
  end
end
