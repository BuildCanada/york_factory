require "test_helper"

class Warehouse::FinancialStatementExtraction::CandidateSetTest < ActiveSupport::TestCase
  setup do
    @release = Warehouse::InstitutionRelease.create!(
      version: "2026-08-30", effective_on: Date.new(2026, 8, 30), schema_version: "1.0",
      published_at: Time.utc(2026, 8, 30), geography_vintage: 2021, attribution: "Test"
    )
    @source = Warehouse::InstitutionSource.create!(
      institution_release: @release, canonical_id: "ca/sources/candidate-test",
      publisher_name: "Test", title_en: "Test", url: "https://example.test/source",
      retrieved_at: @release.published_at, languages: [ "en" ]
    )
    @directory = Pathname(Dir.mktmpdir)
  end

  teardown { FileUtils.remove_entry(@directory) }

  test "selects every preferred local-government PDF and derives missing fiscal dates" do
    municipal = create_institution("ca/on/example", "municipal")
    regional = create_institution("ca/bc/example-regional-district", "regional")
    create_document(municipal, year: 2024, fiscal_period_end: nil, sha: "a" * 64)
    create_document(regional, year: 2023, fiscal_period_end: Date.new(2023, 12, 31), sha: "b" * 64)

    candidates = Warehouse::FinancialStatementExtraction::CandidateSet.new(
      release: @release, asset_root: @directory
    ).each.to_a

    assert_equal 2, candidates.length
    assert_equal [ 2023, 2024 ], candidates.map { _1.fiscal_year_end.year }.sort
    assert_equal %w[ca/bc/example-regional-district ca/on/example],
      candidates.map(&:institution_canonical_id).sort
  end

  test "filters by province and year and audits the archived hash" do
    institution = create_institution("ca/on/example", "municipal")
    create_document(institution, year: 2024, fiscal_period_end: nil, sha: Digest::SHA256.hexdigest("pdf"), contents: "pdf")
    create_document(institution, year: 2023, fiscal_period_end: nil, sha: Digest::SHA256.hexdigest("older"), contents: "older")

    set = Warehouse::FinancialStatementExtraction::CandidateSet.new(
      release: @release, provinces: [ "on" ], years: [ 2024 ], asset_root: @directory
    )
    audit = set.audit(verify_hashes: true)

    assert_equal 1, set.count
    assert_equal 1, audit.fetch(:candidates)
    assert_empty audit.fetch(:missing_files)
    assert_empty audit.fetch(:size_mismatches)
    assert_empty audit.fetch(:hash_mismatches)
  end

  private

  def create_institution(canonical_id, government_level)
    Warehouse::Institution.create!(
      institution_release: @release, institution_source: @source, canonical_id:,
      name_en: canonical_id.split("/").last.titleize, institution_type: "government",
      government_level:, status: "active"
    )
  end

  def create_document(institution, year:, fiscal_period_end:, sha:, contents: "x")
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution:, institution_source: @source,
      canonical_id: "#{institution.canonical_id}/documents/financial-statements/#{year}/general",
      document_type: "financial-statements", document_variant: "general", fiscal_period_end:
    )
    relative = Pathname("sha256/#{sha.first(2)}/#{sha}.pdf")
    path = @directory.join(relative)
    path.dirname.mkpath
    path.write(contents)
    Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: document, content_sha256: sha,
      asset_role: "final", preferred: true, download_url: "https://example.test/#{year}.pdf",
      retrieved_at: @release.published_at, archive_path: relative.to_s,
      mime_type: "application/pdf", byte_size: path.size, rights_status: "metadata_only"
    )
  end
end
