#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "pathname"
require "thread"
require "time"
require "uri"
require_relative "scrape_municipal_financial_reports"

class RevalidateMunicipalFinancialReportCandidates
  def initialize(manifest_path:, previous_batch_path:, output_path:, retrieved_at:, threads: 8,
    asset_root: MunicipalFinancialReportScraper::DEFAULT_ASSET_ROOT)
    @manifest_path = Pathname(manifest_path).expand_path
    @previous_batch_path = Pathname(previous_batch_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @retrieved_at = Time.iso8601(retrieved_at).utc
    @threads = Integer(threads)
    @scraper = MunicipalFinancialReportScraper.new(
      manifest_path: @manifest_path,
      output_dir: @output_path.dirname,
      retrieved_at: @retrieved_at.iso8601,
      asset_root: asset_root
    )
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    previous = JSON.parse(@previous_batch_path.read)
    rows = manifest.fetch("municipalities").to_h { [ _1.fetch("canonical_id"), _1 ] }
    work = previous.fetch("institutions").filter_map do |result|
      row = rows[result.fetch("canonical_id")]
      next unless row
      next if has_financial_statement?(row)

      candidates = rejected_name_candidates(result)
      [ row, result, candidates ] if candidates.any?
    end
    results = parallel_map(work) { |row, prior, candidates| revalidate(row, prior, candidates) }
    reports = results.flat_map { _1.fetch("reports") }
    payload = {
      "batch" => "#{manifest.fetch('province').fetch('code')}-municipal-financial-reports-name-revalidation",
      "source_manifest" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "previous_batch" => @previous_batch_path.to_s,
      "previous_batch_sha256" => Digest::SHA256.file(@previous_batch_path).hexdigest,
      "retrieved_at" => @retrieved_at.iso8601,
      "institution_count" => results.length,
      "institutions_with_reports" => results.count { _1["reports"].any? },
      "validated_report_count" => reports.length,
      "financial_statement_count" => reports.count { _1["document_type"] == "financial-statements" },
      "annual_report_count" => reports.count { _1["document_type"] == "annual-report" },
      "sofi_count" => reports.count { _1["document_type"] == "statement-of-financial-information" },
      "institutions" => results
    }
    @output_path.dirname.mkpath
    @output_path.write(JSON.pretty_generate(payload) << "\n")
    puts JSON.pretty_generate(payload.slice(
      "institution_count", "institutions_with_reports", "validated_report_count",
      "financial_statement_count", "annual_report_count", "sofi_count"
    ).merge("output" => @output_path.to_s, "sha256" => Digest::SHA256.file(@output_path).hexdigest))
  end

  private

  def has_financial_statement?(row)
    row.fetch("documents", []).any? do |document|
      document["document_type"] == "financial-statements" && document.fetch("assets", []).any?
    end
  end

  def rejected_name_candidates(result)
    result.fetch("candidate_errors", []).filter_map do |error|
      url = error[/\A(https?:\/\/.*?): PDF text did not identify /, 1]
      next unless url

      {
        "url" => url,
        "label" => File.basename(URI(url).path),
        "source_page_url" => url
      }
    rescue URI::InvalidURIError
      nil
    end.uniq { _1.fetch("url") }.first(100)
  end

  def revalidate(row, prior, candidates)
    errors = []
    reports = candidates.flat_map do |candidate|
      @scraper.send(:verify_and_archive, row, candidate)
    rescue StandardError => error
      errors << "#{candidate.fetch('url')}: #{error.class}: #{error.message}"
      []
    end
    reports.uniq! { [ _1.fetch("document_type"), _1.fetch("year"), _1.fetch("content_sha256") ] }
    {
      "canonical_id" => row.fetch("canonical_id"),
      "official_name" => row["official_name_en"] || row["official_name_fr"],
      "website_url" => row["website_url"],
      "searched_locations" => prior.fetch("searched_locations", []),
      "candidate_count" => candidates.length,
      "validated_report_count" => reports.length,
      "reports" => reports.sort_by { [ _1.fetch("document_type"), _1.fetch("year"), _1.fetch("download_url") ] },
      "gaps" => reports.empty? ? [ "Previously rejected name candidates still failed validation." ] : [],
      "discovery_errors" => [],
      "candidate_errors" => errors,
      "review_rejections" => []
    }
  end

  def parallel_map(rows)
    queue = Queue.new
    rows.each_with_index { |row, index| queue << [ index, row ] }
    results = Array.new(rows.length)
    Array.new(@threads) do
      Thread.new do
        loop do
          index, row = queue.pop(true)
          results[index] = yield(*row)
        rescue ThreadError
          break
        end
      end
    end.each(&:join)
    results
  end
end

options = { threads: 8 }
OptionParser.new do |parser|
  parser.banner = "Usage: revalidate_municipal_financial_report_candidates.rb --manifest PATH --previous-batch PATH --output PATH --retrieved-at ISO8601"
  parser.on("--manifest PATH") { options[:manifest_path] = _1 }
  parser.on("--previous-batch PATH") { options[:previous_batch_path] = _1 }
  parser.on("--output PATH") { options[:output_path] = _1 }
  parser.on("--retrieved-at TIME") { options[:retrieved_at] = _1 }
  parser.on("--threads N", Integer) { options[:threads] = _1 }
  parser.on("--asset-root PATH") { options[:asset_root] = Pathname(_1) }
end.parse!

missing = %i[manifest_path previous_batch_path output_path retrieved_at].reject { options[_1] }
abort "missing options: #{missing.join(', ')}" if missing.any?

RevalidateMunicipalFinancialReportCandidates.new(**options).run
