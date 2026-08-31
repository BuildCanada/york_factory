require "test_helper"

class Warehouse::FinancialStatementExtraction::QuebecFormPipelineTest < ActiveSupport::TestCase
  test "reads current actual cells from the standardized operations form" do
    page = <<~TEXT
      ÉTAT DES RÉSULTATS
                                              Budget       Réalisations
                                               2023          2023          2022
      Revenus
      Taxes                             1       100           120           110
      Quotes-parts                      3                     (2)             1
                                       13      100           118           111
      Charges
      Administration générale         14       80            90            70
                                       24       80            90            70
      Excédent de l'exercice           25       20            28            41
      Solde redressé                   28                    200           159
      Excédent accumulé                29                    228           200
    TEXT

    form = Warehouse::FinancialStatementExtraction::QuebecFormPipeline::FormPage.new(
      page, 2023, current_column: 1
    )

    assert_equal "120", form.fetch(1).fetch(:raw_text)
    assert_equal "(2)", form.fetch(3).fetch(:raw_text)
    assert_equal "118", form.fetch(13).fetch(:raw_text)
    assert_equal "Administration générale", form.fetch(14).fetch(:label)
  end

  test "reads current cells when older forms omit the budget column" do
    page = <<~TEXT
      ÉTAT CONSOLIDÉ DES RÉSULTATS
                                      Réalisations
                                           2020          2019
      Revenus
      Taxes                        1       120           110
                                  13       120           110
      Charges
      Administration générale    14        90            70
                                  24        90            70
      Excédent de l'exercice      25        30            40
      Solde redressé              28       200           160
      Excédent accumulé           29       230           200
    TEXT

    form = Warehouse::FinancialStatementExtraction::QuebecFormPipeline::FormPage.new(
      page, 2020, current_column: 1
    )

    assert_equal "120", form.fetch(1).fetch(:raw_text)
    assert_equal "90", form.fetch(14).fetch(:raw_text)
    assert_equal "2020", form.fetch(25).fetch(:column_year)
  end

  test "prefers the standardized S7 form when its OCR heading is malformed" do
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 12,
      page_texts: { 7 => "ÉrRr oes nÉsulrRrs\nRapport financier 2025 | S7 I", 8 => "position" },
      position_page: 11, operations_page: 10, candidate_pages: [ 10, 11 ], ocr_pages: []
    )
    pipeline = Warehouse::FinancialStatementExtraction::QuebecFormPipeline.new(
      pdf_path: "unused.pdf", institution_canonical_id: "ca/qc/example",
      document_canonical_id: "ca/qc/example/documents/financial-statements/2025/general",
      asset_sha256: "unused", fiscal_year_end: Date.new(2025, 12, 31)
    )

    preferred = pipeline.send(:prefer_mamh_form_pages, located)

    assert_equal 7, preferred.operations_page
    assert_equal 8, preferred.position_page
    assert_equal [ 6, 7, 8, 9 ], preferred.candidate_pages
  end

  test "reads detailed actual line items from thresholded MAMH table OCR" do
    text = <<~TEXT
      2025                        2025                        2024
      Revenus
      Taxes                  5198100                 5129613                 4877684
      Autres revenus    10      3600                   91608                   84215
      13                 6322000                6688008                 8235164
      Charges
      Administration générale 14 1310250              1259235                 1345416
      24                 5869900                6872536                 6051550
      Excédent (déficit) lié aux activités 25 452100 (184528) 2183614
    TEXT
    page = Warehouse::FinancialStatementExtraction::QuebecFormPipeline::OcrFormPage.new(
      text, 2025, current_column: 1
    )

    revenue = page.section_rows(/\ARevenus\b/i, /\ACharges\b/i)
    expenses = page.section_rows(/\ACharges\b/i, /\AExc[eé]dent\b/i)

    assert_equal [ [ "Taxes", "5129613" ], [ "Autres revenus", "91608" ] ],
      revenue.map { [ _1[:label], _1[:raw_text] ] }
    assert_equal [ [ "Administration générale", "1259235" ] ],
      expenses.map { [ _1[:label], _1[:raw_text] ] }
  end

  test "falls back only for the configured deterministic parser error" do
    primary = Object.new
    primary.define_singleton_method(:run) { raise Warehouse::FinancialStatementExtraction::QuebecFormPipeline::Unsupported, "layout" }
    fallback = Object.new
    fallback.define_singleton_method(:run) { :model_result }
    pipeline = Warehouse::FinancialStatementExtraction::FallbackPipeline.new(
      primary:, fallback:, on: Warehouse::FinancialStatementExtraction::QuebecFormPipeline::Unsupported
    )

    assert_equal :model_result, pipeline.run
  end
end
