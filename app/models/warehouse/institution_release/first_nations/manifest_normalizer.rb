require "json"

module Warehouse::InstitutionRelease::FirstNations
  class ManifestNormalizer
    class NormalizeError < StandardError; end

    attr_reader :output_path

    def initialize(primary_path:, retry_paths: [], output_path: nil)
      @primary_path = Pathname(primary_path)
      @retry_paths = Array(retry_paths).map { |path| Pathname(path) }
      @output_path = output_path && Pathname(output_path)
    end

    def call
      paths = [ @primary_path, *@retry_paths ]
      manifests = paths.map { |path| JSON.parse(path.read) }
      validate_releases!(manifests)
      location_en = location_rows(@primary_path.dirname.join("isc-location-en.json"))
      location_fr = location_rows(@primary_path.dirname.join("isc-location-fr.json"))
      candidates = manifests.flat_map { |manifest| manifest.fetch("bands") }
        .group_by { |band| band.fetch("band_number").to_s }
      skipped = candidates.filter_map do |_number, rows|
        row = rows.first
        next unless row["parent_band_number"].present?
        {
          band_number: row.fetch("band_number"), name_en: row.fetch("name_en"),
          parent_band_number: row.fetch("parent_band_number"),
          parent_band_name: row["parent_band_name"], reason: "ISC parented subgroup; not a standalone band government"
        }
      end
      bands = candidates.filter_map do |number, rows|
        next if rows.first["parent_band_number"].present?
        merge_band(rows, location_en.fetch(number), location_fr[number], paths)
      end.sort_by { |band| Integer(band.fetch(:band_number)) }

      collisions = bands.group_by { |band| semantic_slug(band.fetch(:name_en)) }
        .select { |_slug, rows| rows.many? }
        .map { |slug, rows| { semantic_slug: slug, band_numbers: rows.map { |row| row.fetch(:band_number) } } }
      payload = manifests.first.merge(
        "scope" => "national-normalized-bands",
        "normalized_at" => Time.current.utc.iso8601,
        "source_manifest_paths" => paths.map(&:to_s),
        "bands" => bands,
        "skipped_entities" => skipped,
        "normalization_summary" => summary(bands, skipped, collisions),
        "canonical_id_collisions" => collisions
      )
      @output_path ||= @primary_path.dirname.join("normalized-manifest.json")
      raise NormalizeError, "normalized manifest already exists: #{@output_path}" if @output_path.exist?

      @output_path.write(JSON.pretty_generate(payload) << "\n")
      @output_path
    rescue Errno::ENOENT, JSON::ParserError, KeyError => error
      raise NormalizeError, error.message
    end

    private

    def validate_releases!(manifests)
      versions = manifests.map { |manifest| manifest.fetch("release_version") }.uniq
      raise NormalizeError, "source manifests have different release versions" unless versions.one?
    end

    def location_rows(path)
      JSON.parse(path.read).fetch("pages").flat_map { |page| page.fetch("features") }
        .to_h { |feature| [ feature.fetch("attributes").fetch("BAND_NUMBER").to_s, feature.fetch("attributes") ] }
    end

    def merge_band(rows, location_en, location_fr, paths)
      base = rows.max_by do |row|
        [ row["website_url"].present? ? 1 : 0, row.fetch("reports").length,
          row.fetch("statcan_geographies").any? ? 1 : 0, -row.fetch("gaps").count { |gap| gap.include?("unavailable") } ]
      end.deep_symbolize_keys
      base[:website_url] = rows.filter_map { |row| row["website_url"].presence }.first
      base[:contact] = rows.map { |row| row.fetch("contact", {}) }.reduce({}) { |merged, contact| merged.merge(contact.compact) }
      base[:reports] = rows.flat_map { |row| row.fetch("reports") }
        .group_by { |report| report.fetch("canonical_id") }
        .values.map { |reports| reports.max_by { |report| report.compact.length } }
        .sort_by { |report| report.fetch("fiscal_year_label") }
      base[:statcan_geographies] = rows.find { |row| row.fetch("statcan_geographies").any? }
        &.fetch("statcan_geographies") || []
      base[:gaps] = merged_gaps(rows)
      base[:province_code] = location_en["CPC_CODE"].to_s.downcase.presence
      base[:province_name_en] = location_en["PRNAME_EN"].to_s.tr("\u00A0", " ").presence
      base[:province_name_fr] = location_fr&.fetch("PRNAME_FR", nil).to_s.tr("\u00A0", " ").presence
      base[:provenance] = base.fetch(:provenance).merge(source_manifest_paths: paths.map(&:to_s))
      base.compact
    end

    def merged_gaps(rows)
      gap_sets = rows.map { |row| row.fetch("gaps") }
      intrinsic = gap_sets.flat_map { |gaps| gaps.reject { |gap| gap.include?("unavailable") } }
      missing_link = intrinsic.grep(/FNFTA audited-statement rows had no downloadable document/)
        .min_by { |gap| gap.to_i }
      other = intrinsic.reject { |gap| gap.include?("FNFTA audited-statement rows had no downloadable document") }.uniq
      unavailable = gap_sets.flatten.select { |gap| gap.include?("unavailable") }.group_by do |gap|
        gap.sub(/ unavailable:.*/, " unavailable")
      end.filter_map do |prefix, gaps|
        prefix if rows.all? { |row| row.fetch("gaps").any? { |gap| gap.start_with?(prefix.delete_suffix(" unavailable")) && gap.include?("unavailable") } }
      end
      [ missing_link, *other, *unavailable ].compact
    end

    def semantic_slug(name)
      ActiveSupport::Inflector.transliterate(name).downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    end

    def summary(bands, skipped, collisions)
      reports = bands.flat_map { |band| band.fetch(:reports) }
      {
        band_count: bands.length,
        skipped_non_band_count: skipped.length,
        website_count: bands.count { |band| band[:website_url].present? },
        geography_count: bands.count { |band| band.fetch(:statcan_geographies).any? },
        bands_with_reports: bands.count { |band| band.fetch(:reports).any? },
        report_count: reports.length,
        report_fiscal_years: reports.map { |report| report.fetch("fiscal_year_label") }.uniq.sort,
        canonical_id_collision_count: collisions.length,
        by_province_or_territory: bands.group_by { |band| band[:province_code] }.transform_values(&:length).sort.to_h
      }
    end
  end
end
