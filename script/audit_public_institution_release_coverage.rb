#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"

release_dir, output_path = ARGV
abort "Usage: audit_public_institution_release_coverage.rb RELEASE_DIR OUTPUT_PATH" unless release_dir && output_path

release_dir = Pathname(release_dir).expand_path
output_path = Pathname(output_path).expand_path
abort "Missing release manifest" unless release_dir.join("manifest.json").file?
abort "Refusing to overwrite #{output_path}" if output_path.exist?

def query(release_dir, sql)
  stdout, stderr, status = Open3.capture3("duckdb", "-json", "-c", sql, chdir: release_dir.to_s)
  abort "DuckDB audit failed: #{stderr}" unless status.success?

  json = stdout.lines.drop_while { |line| !line.start_with?("[", "{") }.join
  abort "DuckDB audit returned no JSON: #{stdout}" if json.empty?
  JSON.parse(json)
end

gap_rows = query(release_dir, <<~SQL)
  WITH document_rollup AS (
    SELECT
      d.reporting_institution_id AS institution_id,
      count(*) FILTER (WHERE d.document_type = 'financial-statements') AS financial_statement_works,
      count(*) FILTER (
        WHERE d.document_type = 'financial-statements'
          AND EXISTS (
            SELECT 1 FROM read_parquet('document_assets.parquet') a
            WHERE a.release_version = d.release_version AND a.document_id = d.canonical_id
          )
      ) AS financial_statement_works_with_assets,
      count(*) FILTER (WHERE d.document_type = 'annual-report') AS annual_report_works,
      count(*) FILTER (
        WHERE d.document_type = 'annual-report'
          AND EXISTS (
            SELECT 1 FROM read_parquet('document_assets.parquet') a
            WHERE a.release_version = d.release_version AND a.document_id = d.canonical_id
          )
      ) AS annual_report_works_with_assets
    FROM read_parquet('documents.parquet') d
    GROUP BY d.reporting_institution_id
  ), geography_rollup AS (
    SELECT institution_id, count(*) AS geography_links
    FROM read_parquet('institution_geographies.parquet')
    GROUP BY institution_id
  ), identifier_rollup AS (
    SELECT institution_id, count(*) AS identifiers
    FROM read_parquet('identifiers.parquet')
    GROUP BY institution_id
  )
  SELECT
    i.canonical_id,
    coalesce(i.name_en, i.name_fr) AS name,
    split_part(i.canonical_id, '/', 2) AS namespace,
    i.government_level,
    i.legal_form,
    i.status,
    i.website_url,
    i.source_id,
    coalesce(ir.identifiers, 0) AS identifier_count,
    coalesce(gr.geography_links, 0) AS geography_link_count,
    coalesce(dr.financial_statement_works, 0) AS financial_statement_works,
    coalesce(dr.financial_statement_works_with_assets, 0) AS financial_statement_works_with_assets,
    coalesce(dr.annual_report_works, 0) AS annual_report_works,
    coalesce(dr.annual_report_works_with_assets, 0) AS annual_report_works_with_assets,
    list_filter([
      CASE WHEN i.website_url IS NULL OR trim(i.website_url) = '' THEN 'website' END,
      CASE WHEN coalesce(ir.identifiers, 0) = 0 THEN 'identifier' END,
      CASE WHEN coalesce(gr.geography_links, 0) = 0 THEN 'geography' END,
      CASE WHEN coalesce(dr.financial_statement_works, 0) = 0 THEN 'financial-statements' END,
      CASE WHEN coalesce(dr.financial_statement_works, 0) > coalesce(dr.financial_statement_works_with_assets, 0)
        THEN 'financial-statement-assets' END,
      CASE WHEN coalesce(dr.annual_report_works, 0) = 0 THEN 'annual-reports' END
    ], lambda value: value IS NOT NULL) AS gaps
  FROM read_parquet('institutions.parquet') i
  LEFT JOIN document_rollup dr ON dr.institution_id = i.canonical_id
  LEFT JOIN geography_rollup gr ON gr.institution_id = i.canonical_id
  LEFT JOIN identifier_rollup ir ON ir.institution_id = i.canonical_id
  ORDER BY namespace, i.canonical_id
SQL

coverage = query(release_dir, <<~SQL)
  SELECT scope_id, subject, status, notes, source_url, source_id
  FROM read_parquet('coverage.parquet')
  ORDER BY scope_id, subject
SQL

summary = gap_rows.group_by { |row| row.fetch("namespace") }.transform_values do |rows|
  {
    "institutions" => rows.length,
    "websites" => rows.count { |row| row["website_url"] },
    "with_financial_statements" => rows.count { |row| row.fetch("financial_statement_works").positive? },
    "with_downloaded_financial_statements" => rows.count do |row|
      row.fetch("financial_statement_works_with_assets").positive?
    end,
    "missing_websites" => rows.count { |row| row["website_url"].nil? },
    "missing_financial_statements" => rows.count { |row| row.fetch("financial_statement_works").zero? }
  }
end

manifest_path = release_dir.join("manifest.json")
payload = {
  "release_version" => JSON.parse(manifest_path.read).fetch("release"),
  "source_release_manifest" => manifest_path.to_s,
  "source_release_manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
  "generated_at" => "2026-08-24T12:00:00Z",
  "summary_by_namespace" => summary.sort.to_h,
  "coverage_assertions" => coverage,
  "institution_gaps" => gap_rows
}

FileUtils.mkdir_p(output_path.dirname)
output_path.write(JSON.pretty_generate(payload) + "\n")
puts JSON.generate(
  output_path: output_path.to_s,
  institutions: gap_rows.length,
  missing_websites: gap_rows.count { |row| row["website_url"].nil? },
  missing_financial_statements: gap_rows.count { |row| row.fetch("financial_statement_works").zero? },
  sha256: Digest::SHA256.file(output_path).hexdigest
)
