require "test_helper"

class Warehouse::FinancialStatementExtractionTest < ActiveSupport::TestCase
  setup do
    @release = Warehouse::InstitutionRelease.create!(
      version: "2026-08-27", effective_on: Date.new(2026, 8, 27), schema_version: "1.0",
      published_at: Time.utc(2026, 8, 27), geography_vintage: 2021, attribution: "Test"
    )
    source = Warehouse::InstitutionSource.create!(
      institution_release: @release, canonical_id: "ca/sources/test",
      publisher_name: "Test", title_en: "Test", url: "https://example.test/source",
      retrieved_at: @release.published_at, languages: [ "en" ]
    )
    @institution = Warehouse::Institution.create!(
      institution_release: @release, institution_source: source, canonical_id: "ca/on/example",
      name_en: "Example", institution_type: "government", government_level: "municipal", status: "active"
    )
    @document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution: @institution, institution_source: source,
      canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      document_type: "financial-statements", document_variant: "general"
    )
    @asset = Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: @document, content_sha256: "a" * 64,
      asset_role: "final", preferred: true, download_url: "https://example.test/statement.pdf",
      retrieved_at: @release.published_at, archive_path: "sha256/aa/#{'a' * 64}.pdf",
      mime_type: "application/pdf", byte_size: 1, rights_status: "metadata_only"
    )
  end

  test "reviewed extractions cannot be rerun in place" do
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release,
      institution_canonical_id: @institution.canonical_id,
      document_canonical_id: @document.canonical_id,
      asset_sha256: @asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31),
      extractor_version: "test-v1",
      status: "extracted"
    )
    extraction.approve!(reviewer: "reviewer")

    error = assert_raises(ArgumentError) do
      extraction.extractor.extract(pdf_path: "missing.pdf", institution_name: "Example")
    end
    assert_includes error.message, "immutable"
    assert_equal "approved", extraction.reload.status
  end

  test "source asset and institution must belong to the extraction release document" do
    extraction = Warehouse::FinancialStatementExtraction.new(
      institution_release: @release, institution_canonical_id: "ca/on/different",
      document_canonical_id: @document.canonical_id, asset_sha256: "b" * 64,
      fiscal_year_end: Date.new(2025, 12, 31), extractor_version: "test-v1", status: "extracted"
    )

    refute extraction.valid?
    assert_includes extraction.errors[:institution_canonical_id],
      "must identify the release document's reporting institution"
    assert_includes extraction.errors[:asset_sha256],
      "must identify an archived asset on the release document"
  end
end
