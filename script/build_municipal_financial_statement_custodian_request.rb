#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "digest"
require "fileutils"
require "json"
require "optparse"

class BuildMunicipalFinancialStatementCustodianRequest
  PROVINCES = {
    "nl" => {
      addressee: "Municipal Finance Division, Department of Municipal and Community Affairs",
      contact: "MCAInfo@gov.nl.ca (administrative request); atippmca@gov.nl.ca if formal access processing is required",
      authority_url: "https://www.gov.nl.ca/mca/department/contact/",
      rationale: "The department identifies a Municipal Finance Division and regional offices that support municipalities on financial matters."
    },
    "pe" => {
      addressee: "Municipal Affairs, Government of Prince Edward Island",
      contact: "municipalaffairs@gov.pe.ca",
      authority_url: "https://www.princeedwardisland.ca/en/information/housing-land-and-communities/financial-plan-budget-and-financial-reporting",
      rationale: "Municipalities must submit audited financial statements to Municipal Affairs, and the department publishes submitted statements."
    },
    "nb" => {
      addressee: "Commissioner of Municipal Affairs / Local Government Finance, Government of New Brunswick",
      contact: "Route to the current records holder through the Government of New Brunswick public-bodies directory; this draft is not addressed to an individual employee.",
      authority_url: "https://www.gnb.ca/en/gov/information-access-privacy/public-bodies-directory.html",
      rationale: "New Brunswick's municipal accounting framework requires municipal returns and financial information to be furnished to the Commissioner."
    },
    "sk" => {
      addressee: "Advisory Services and Municipal Relations, Ministry of Government Relations, Government of Saskatchewan",
      contact: "Route through the current Municipal Inquiry contact listed on Saskatchewan.ca; this draft is not addressed to an individual employee.",
      authority_url: "https://www.saskatchewan.ca/government/municipal-administration/funding-finances-and-asset-management/financial",
      rationale: "The Cities Act and The Municipalities Act require municipalities to submit annual audited financial statements and the auditor's report to Government Relations; Saskatchewan states that the published 2022–2024 collection contains the same statements submitted to the ministry."
    }
  }.freeze

  TARGET_YEARS = (2016..2025).to_a.freeze

  def initialize(manifest:, gap_ids:, province:, output_dir:)
    @manifest_path = manifest
    @gap_ids_path = gap_ids
    @province = province
    @profile = PROVINCES.fetch(province)
    @output_dir = output_dir
    @manifest = JSON.parse(File.read(manifest))
    @gap_ids = File.readlines(gap_ids, chomp: true).map(&:strip).reject(&:empty?).uniq
  end

  def call
    rows = @manifest.fetch("municipalities")
    by_id = rows.to_h { [ _1.fetch("canonical_id"), _1 ] }
    missing = @gap_ids - by_id.keys
    raise "gap IDs absent from manifest: #{missing.join(', ')}" unless missing.empty?

    predecessors = @manifest.fetch("relationships", []).select { _1["relationship_type"] == "succeeds" }
      .group_by { _1.fetch("source_id") }
    inventory = @gap_ids.sort.flat_map do |subject_id|
      subject = by_id.fetch(subject_id)
      edges = predecessors.fetch(subject_id, [])
      own_start = edges.filter_map { _1["valid_from"]&.to_s&.slice(0, 4)&.to_i }.min || TARGET_YEARS.min
      items = [ inventory_row(subject, subject, "self", TARGET_YEARS.select { _1 >= own_start }) ]
      items.concat(edges.map do |edge|
        predecessor = by_id.fetch(edge.fetch("target_id"))
        end_year = edge.fetch("valid_from").to_s.slice(0, 4).to_i - 1
        inventory_row(subject, predecessor, "predecessor", TARGET_YEARS.select { _1 <= end_year })
      end)
      items
    end.select { _1.fetch("requested_fiscal_years").any? }

    FileUtils.mkdir_p(@output_dir)
    write_json(inventory)
    write_csv(inventory)
    write_draft(inventory)
    write_readme(inventory)
    summary(inventory)
  end

  private

  def inventory_row(subject, issuer, relationship, eligible_years)
    downloaded = issuer.fetch("documents", []).filter_map do |document|
      next unless document["document_type"] == "financial-statements"
      next unless document.fetch("assets", []).any?

      value = document["fiscal_period_end"] || document["published_on"] || document["canonical_id"]
      value.to_s[/[12]\d{3}/]&.to_i
    end.uniq.sort
    {
      "subject_canonical_id" => subject.fetch("canonical_id"),
      "subject_legal_name" => legal_name(subject),
      "issuer_canonical_id" => issuer.fetch("canonical_id"),
      "issuer_legal_name" => legal_name(issuer),
      "relationship_to_subject" => relationship,
      "downloaded_fiscal_years" => downloaded,
      "requested_fiscal_years" => eligible_years - downloaded,
      "requested_document_type" => "audited financial statements",
      "preferred_file_format" => "original PDF"
    }
  end

  def legal_name(row)
    row["official_name_en"] || row["official_name"] || row["official_name_fr"] || raise("name missing for #{row['canonical_id']}")
  end

  def write_json(inventory)
    payload = {
      "artifact" => "municipal_financial_statement_custodian_gap_inventory",
      "version" => 1,
      "status" => "draft_not_sent",
      "province" => @province,
      "target_fiscal_year_window" => TARGET_YEARS,
      "identity_rule" => "Each requested file is indexed under its legal issuer. Predecessor files are not relabelled as successor-issued.",
      "source_manifest" => @manifest_path,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "source_gap_ids" => @gap_ids_path,
      "source_gap_ids_sha256" => Digest::SHA256.file(@gap_ids_path).hexdigest,
      "request_rows" => inventory
    }
    File.write(File.join(@output_dir, "gap-inventory.json"), JSON.pretty_generate(payload) + "\n")
  end

  def write_csv(inventory)
    headers = %w[subject_canonical_id subject_legal_name issuer_canonical_id issuer_legal_name relationship_to_subject downloaded_fiscal_years requested_fiscal_years requested_document_type preferred_file_format]
    CSV.open(File.join(@output_dir, "gap-inventory.csv"), "w", write_headers: true, headers: headers) do |csv|
      inventory.each do |row|
        csv << headers.map { |header| row.fetch(header).is_a?(Array) ? row.fetch(header).join(";") : row.fetch(header) }
      end
    end
  end

  def write_draft(inventory)
    unique_issuers = inventory.map { _1.fetch("issuer_canonical_id") }.uniq.length
    requested_files = inventory.sum { _1.fetch("requested_fiscal_years").length }
    body = <<~MARKDOWN
      # DRAFT — NOT SENT: bulk municipal audited-financial-statement request (#{@province.upcase})

      To: #{@profile.fetch(:addressee)}
      Contact/routing: #{@profile.fetch(:contact)}

      Subject: Request for machine-readable copies of municipal audited financial statements, fiscal years 2016–2025

      Hello,

      We are assembling a public, versioned dataset of Canadian public institutions and their source financial documents. Please provide the audited financial statements in your custody for the legal issuers and fiscal years itemized in the attached `gap-inventory.csv` (also supplied as JSON).

      The inventory contains #{inventory.length} issuer-specific rows covering #{unique_issuers} legal issuers and #{requested_files} requested issuer-year files. It distinguishes current municipalities from predecessor corporations so that historical statements are not misattributed to a post-restructuring successor.

      Please deliver records electronically in their original files, preferably original PDFs rather than rescanned copies. A ZIP archive, object-storage download, SFTP transfer, or other bulk link is welcome. Please include a CSV index with, where available: legal issuer name, fiscal period start, fiscal period end, auditor, original filename, source-system identifier, and any public source URL. Bilingual copies should be included only where the upstream record itself is bilingual or separate English/French originals exist.

      If the exact requested item is unavailable, please provide the closest retained version and note the retention gap in the index. Duplicate files need only be delivered once if the index maps the same file to every applicable issuer/year. No new analysis or record creation is requested.

      This can be handled first as an ordinary administrative/public-data request. If formal access-to-information processing is required, please advise before incurring fees and provide an estimate. Electronic disclosure is strongly preferred.

      Thank you.

      ## Custody basis

      #{@profile.fetch(:rationale)}

      Source: #{@profile.fetch(:authority_url)}

      ## Attachments

      - `gap-inventory.csv`
      - `gap-inventory.json`
    MARKDOWN
    File.write(File.join(@output_dir, "request-draft.md"), body)
  end

  def write_readme(inventory)
    text = <<~MARKDOWN
      # Custodian request bundle — #{@province.upcase}

      Status: draft only; not sent.

      The request targets fiscal years #{TARGET_YEARS.first}–#{TARGET_YEARS.last}. It was generated from the pinned manifest and the national ten-year gap-ID worklist. Rows are issuer-specific: a predecessor is a separate canonical institution, connected to the current subject only through a sourced `succeeds` relationship.

      Counts: #{@gap_ids.length} current gap subjects; #{inventory.length} issuer rows; #{inventory.sum { _1.fetch('requested_fiscal_years').length }} requested issuer-year files.
    MARKDOWN
    File.write(File.join(@output_dir, "README.md"), text)
  end

  def summary(inventory)
    {
      province: @province,
      subject_count: @gap_ids.length,
      issuer_row_count: inventory.length,
      unique_issuer_count: inventory.map { _1.fetch("issuer_canonical_id") }.uniq.length,
      requested_issuer_year_count: inventory.sum { _1.fetch("requested_fiscal_years").length },
      output_dir: @output_dir
    }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby script/build_municipal_financial_statement_custodian_request.rb --province nl|pe|nb|sk --manifest PATH --gap-ids PATH --output-dir PATH"
    parser.on("--province CODE") { options[:province] = _1 }
    parser.on("--manifest PATH") { options[:manifest] = _1 }
    parser.on("--gap-ids PATH") { options[:gap_ids] = _1 }
    parser.on("--output-dir PATH") { options[:output_dir] = _1 }
  end.parse!
  missing = %i[province manifest gap_ids output_dir].reject { options[_1] }
  abort "missing options: #{missing.join(', ')}" unless missing.empty?
  abort "unsupported province" unless BuildMunicipalFinancialStatementCustodianRequest::PROVINCES.key?(options[:province])
  abort "refusing to write into existing output directory" if Dir.exist?(options[:output_dir])

  puts JSON.pretty_generate(BuildMunicipalFinancialStatementCustodianRequest.new(**options).call)
end
