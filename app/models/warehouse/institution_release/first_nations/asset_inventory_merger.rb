require "digest"
require "fileutils"
require "json"
require "zip"

module Warehouse::InstitutionRelease::FirstNations
  class AssetInventoryMerger
    class MergeError < StandardError; end

    def initialize(manifest_path:, inventory_paths:, output_path:, audit_path:,
      asset_root: FinancialStatementArchiver::DEFAULT_ASSET_ROOT)
      @manifest_path = Pathname(manifest_path)
      @inventory_paths = Array(inventory_paths).map { |path| Pathname(path) }
      @output_path = Pathname(output_path)
      @audit_path = Pathname(audit_path)
      @asset_root = Pathname(asset_root).expand_path
    end

    def call
      raise MergeError, "final inventory already exists: #{@output_path}" if @output_path.exist?
      raise MergeError, "audit already exists: #{@audit_path}" if @audit_path.exist?

      manifest = JSON.parse(@manifest_path.read)
      reports, report_bands = report_indexes(manifest)
      attempts = load_attempts(manifest.fetch("release_version"))
      missing = reports.keys - attempts.keys
      extra = attempts.keys - reports.keys
      raise MergeError, "documents without an archive attempt: #{missing.join(', ')}" if missing.any?
      raise MergeError, "archive attempts for unknown documents: #{extra.join(', ')}" if extra.any?

      assets = reports.keys.sort.map { |document_id| merge_attempts(document_id, attempts.fetch(document_id)) }
      audit = audit!(manifest, reports, report_bands, assets)
      @output_path.write(JSON.pretty_generate({
        release_version: manifest.fetch("release_version"),
        manifest_path: @manifest_path.to_s,
        generated_at: Time.current.utc.iso8601,
        source_inventory_paths: @inventory_paths.map(&:to_s),
        assets: assets
      }) << "\n")
      @audit_path.write(JSON.pretty_generate(audit) << "\n")
      [ @output_path, @audit_path ]
    rescue Errno::ENOENT, JSON::ParserError, KeyError => error
      raise MergeError, error.message
    end

    private

    def report_indexes(manifest)
      reports = {}
      report_bands = {}
      manifest.fetch("bands").each do |band|
        band.fetch("reports").each do |report|
          id = report.fetch("canonical_id")
          raise MergeError, "duplicate document in normalized manifest: #{id}" if reports.key?(id)
          reports[id] = report
          report_bands[id] = band
        end
      end
      [ reports, report_bands ]
    end

    def load_attempts(release_version)
      @inventory_paths.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |path, grouped|
        inventory = JSON.parse(path.read)
        raise MergeError, "inventory release mismatch: #{path}" unless inventory.fetch("release_version") == release_version
        inventory.fetch("assets").each do |row|
          grouped[row.fetch("document_canonical_id")] << row.merge("inventory_path" => path.to_s)
        end
      end
    end

    def merge_attempts(document_id, attempts)
      selected = attempts.reverse.find { |attempt| attempt["error"].blank? } || attempts.last
      normalize_office_asset(selected.except("inventory_path")).merge(
        "document_canonical_id" => document_id,
        "archive_pass_count" => attempts.length,
        "attempt_errors" => attempts.filter_map do |attempt|
          next if attempt["error"].blank?
          { "inventory_path" => attempt.fetch("inventory_path"), "error" => attempt.fetch("error") }
        end
      )
    end

    def audit!(manifest, reports, report_bands, assets)
      successes = assets.reject { |asset| asset["error"].present? }
      failures = assets.select { |asset| asset["error"].present? }
      successes.each { |asset| validate_asset!(asset) }
      by_province = assets.group_by do |asset|
        report_bands.fetch(asset.fetch("document_canonical_id")).fetch("province_code")
      end.transform_values { |rows| outcome_counts(rows) }.sort.to_h
      by_fiscal_year = assets.group_by do |asset|
        reports.fetch(asset.fetch("document_canonical_id")).fetch("fiscal_year_label")
      end.transform_values { |rows| outcome_counts(rows) }.sort.to_h

      {
        release_version: manifest.fetch("release_version"),
        audited_at: Time.current.utc.iso8601,
        manifest_path: @manifest_path.to_s,
        inventory_path: @output_path.to_s,
        band_count: manifest.fetch("bands").length,
        skipped_non_band_count: manifest.fetch("skipped_entities").length,
        website_count: manifest.fetch("bands").count { |band| band["website_url"].present? },
        geography_count: manifest.fetch("bands").count { |band| band.fetch("statcan_geographies").any? },
        canonical_id_collision_count: manifest.fetch("canonical_id_collisions").length,
        document_count: assets.length,
        successful_asset_count: successes.length,
        failed_asset_count: failures.length,
        unique_content_hash_count: successes.map { |asset| asset.fetch("content_sha256") }.uniq.length,
        successful_bytes: successes.sum { |asset| Integer(asset.fetch("byte_size")) },
        mime_types: successes.map { |asset| asset.fetch("mime_type") }.tally.sort.to_h,
        failure_reasons: failures.map { |asset| normalize_error(asset.fetch("error")) }.tally.sort.to_h,
        fiscal_years: reports.values.map { |report| report.fetch("fiscal_year_label") }.uniq.sort,
        by_province_or_territory: by_province,
        by_fiscal_year: by_fiscal_year,
        validations: {
          unique_document_ids: assets.map { |asset| asset.fetch("document_canonical_id") }.uniq.length == assets.length,
          all_success_files_exist: true,
          all_success_sizes_match: true,
          all_success_sha256_match: true,
          all_pdf_magic_valid: true,
          all_office_open_xml_magic_valid: true,
          every_document_has_success_or_explicit_failure: assets.length == reports.length
        }
      }
    end

    def outcome_counts(rows)
      successes = rows.reject { |row| row["error"].present? }
      {
        "documents" => rows.length,
        "successful_assets" => successes.length,
        "failures" => rows.length - successes.length,
        "bytes" => successes.sum { |row| Integer(row.fetch("byte_size")) }
      }
    end

    def validate_asset!(asset)
      path = @asset_root.join(asset.fetch("archive_path"))
      raise MergeError, "asset missing: #{path}" unless path.file?
      raise MergeError, "asset size mismatch: #{path}" unless path.size == Integer(asset.fetch("byte_size"))
      raise MergeError, "asset SHA-256 mismatch: #{path}" unless Digest::SHA256.file(path).hexdigest == asset.fetch("content_sha256")

      magic = path.open("rb") { |file| file.read(5) }
      case asset.fetch("mime_type")
      when "application/pdf"
        raise MergeError, "invalid PDF magic: #{path}" unless magic == "%PDF-"
      when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        raise MergeError, "invalid XLSX magic: #{path}" unless magic.start_with?("PK\x03\x04".b)
      when "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        raise MergeError, "invalid DOCX magic: #{path}" unless magic.start_with?("PK\x03\x04".b)
      else
        raise MergeError, "unsupported archived statement MIME: #{asset.fetch('mime_type')}"
      end
    end

    def normalize_error(error)
      error.sub(/ for https:.*/, "")
    end

    def normalize_office_asset(asset)
      return asset unless asset["mime_type"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

      source = @asset_root.join(asset.fetch("archive_path"))
      entries = Zip::File.open(source) { |archive| archive.entries.map(&:name) }
      return asset if entries.include?("xl/workbook.xml")
      raise MergeError, "unrecognized OOXML package: #{source}" unless entries.include?("word/document.xml")

      corrected_path = Pathname(asset.fetch("archive_path")).sub_ext(".docx")
      destination = @asset_root.join(corrected_path)
      destination.dirname.mkpath
      FileUtils.cp(source, destination) unless destination.exist?
      asset.merge(
        "archive_path" => corrected_path.to_s,
        "mime_type" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      )
    end
  end
end
