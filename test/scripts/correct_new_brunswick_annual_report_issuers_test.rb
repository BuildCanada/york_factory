# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../script/correct_new_brunswick_annual_report_issuers"

class CorrectNewBrunswickAnnualReportIssuersTest < Minitest::Test
  ExtractorStub = Class.new(CorrectNewBrunswickAnnualReportIssuers) do
    private

    def extract_text(asset)
      _target, pattern, = self.class.superclass::DECISIONS.fetch(asset.fetch("content_sha256"))
      {
        /city of edmundston/i => "City of Edmundston",
        /before the amalgamation with rivière-verte/i => "before the amalgamation with Rivière-Verte",
        /avant le regroupement avec rivière-verte/i => "avant le regroupement avec Rivière-Verte",
        /patrimoine shippagan inc/i => "Patrimoine Shippagan Inc",
        /village de le goulet/i => "Village de Le Goulet",
        /rapport annuel de la ville de\s+shippagan/i => "rapport annuel de la Ville de\nShippagan",
        /ville de shippagan/i => "Ville de Shippagan"
      }.fetch(pattern)
    end
  end

  def test_splits_mixed_works_and_excludes_nonmunicipal_assets_without_deleting_bytes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "manifest.json")
      File.write(path, JSON.generate(synthetic_manifest))
      result, audit = ExtractorStub.new(manifest: path, asset_root: dir).call

      assert_equal 8, audit.fetch("moved_municipal_asset_link_count")
      assert_equal 3, audit.fetch("excluded_nonmunicipal_asset_link_count")
      assert_equal 0, audit.fetch("archived_byte_deletion_count")
      assert_empty pre_reform_annuals(institution(result, "ca/nb/edmundston"))
      assert_empty pre_reform_annuals(institution(result, "ca/nb/shippagan"))
      assert_equal [ 2018, 2019, 2021, 2022 ], years(institution(result, CorrectNewBrunswickAnnualReportIssuers::OLD_EDMUNDSTON))
      assert_equal [ 2021, 2022 ], years(institution(result, CorrectNewBrunswickAnnualReportIssuers::OLD_SHIPPAGAN))
      assert_equal [ 2018 ], years(institution(result, CorrectNewBrunswickAnnualReportIssuers::LE_GOULET))
    end
  end

  private

  def synthetic_manifest
    digests = CorrectNewBrunswickAnnualReportIssuers::DECISIONS.keys
    rows = [
      institution_row("ca/nb/edmundston", [ work("ca/nb/edmundston", 2018, digests[0]), work("ca/nb/edmundston", 2019, digests[1]), work("ca/nb/edmundston", 2021, digests[2]), work("ca/nb/edmundston", 2022, digests[3], digests[4]) ]),
      institution_row("ca/nb/shippagan", [ work("ca/nb/shippagan", 2018, digests[5], digests[6]), work("ca/nb/shippagan", 2019, digests[7]), work("ca/nb/shippagan", 2021, digests[8], digests[9]), work("ca/nb/shippagan", 2022, digests[10]) ]),
      institution_row(CorrectNewBrunswickAnnualReportIssuers::OLD_EDMUNDSTON, [], "dissolved"),
      institution_row(CorrectNewBrunswickAnnualReportIssuers::OLD_SHIPPAGAN, [], "dissolved"),
      institution_row(CorrectNewBrunswickAnnualReportIssuers::LE_GOULET, [], "dissolved")
    ]
    { "municipalities" => rows, "coverage" => [] }
  end

  def institution_row(id, documents, status = "active")
    { "canonical_id" => id, "official_name_en" => id.split("/").last, "status" => status, "documents" => documents }
  end

  def work(id, year, *digests)
    {
      "canonical_id" => "#{id}/documents/annual-report/#{year}/general",
      "document_type" => "annual-report",
      "assets" => digests.map { { "content_sha256" => _1, "archive_path" => "sha256/#{_1}.pdf", "languages" => [ "en" ] } }
    }
  end

  def institution(result, id)
    result.fetch("municipalities").find { _1.fetch("canonical_id") == id } || flunk("missing #{id}")
  end

  def pre_reform_annuals(row)
    row.fetch("documents").select { _1["document_type"] == "annual-report" && _1["canonical_id"][%r{/([12]\d{3})/}, 1].to_i < 2023 }
  end

  def years(row)
    row.fetch("documents").map { _1.fetch("canonical_id")[%r{/([12]\d{3})/}, 1].to_i }.sort
  end
end
