require "test_helper"

class Polls::CrosstabsWorkbookTest < ActiveSupport::TestCase
  test "Excel opens with summary and index followed by numeric question sheets" do
    poll = Poll.create!(slug: "workbook", survey_slug: "survey", title_en: "Opinion poll", published_at: Time.zone.parse("2026-09-06"))
    table = { id: "duplicate/invalid:sheet-name", type: "multiple", question: { en: "=Dangerous label", fr: "Question française" },
      columns: [ { key: "all", label: { en: "Total" } }, { key: "missing", label: { en: "Missing" } } ],
      rows: [ { label: { en: "Weighted sample size" }, kind: "weighted-sample-size", values: { all: 100, missing: nil } },
        { label: { en: "Support" }, kind: "weighted-percent", values: { all: 67, missing: nil } },
        { label: { en: "Oppose" }, kind: "weighted-percent", values: { all: 0, missing: nil } } ] }
    report = { schemaVersion: 2, survey: { slug: "survey" }, warnings: [ "Small bases" ], tables: [ table, table ], weighting: { method: "none", unweightedResponses: 100 } }
    poll.crosstabs_json.attach(io: StringIO.new(report.to_json), filename: "tabs.json", content_type: "application/json", identify: false)
    bytes = Polls::CrosstabsWorkbook.new(poll).render
    Tempfile.create([ "crosstabs", ".xlsx" ]) do |file|
      file.binmode; file.write(bytes); file.flush
      workbook = Roo::Excelx.new(file.path)
      assert_equal [ "Summary & Index", "Q1", "Q2" ], workbook.sheets
      assert_equal "Build Canada", workbook.sheet(0).cell(1, 1)
      assert_equal "Opinion poll", workbook.sheet(0).cell(1, 2)
      assert_equal "2026-09-06", workbook.sheet(0).cell(2, 2)
      assert_includes workbook.sheet(1).cell(2, 2), "=Dangerous label"
      assert_equal 67, workbook.sheet(1).cell(7, 2)
      assert_equal 0, workbook.sheet(1).cell(8, 2)
      assert_nil workbook.sheet(1).cell(7, 3)
      Zip::File.open(file.path) do |zip|
        xml = zip.read("xl/worksheets/sheet2.xml")
        assert_not_includes xml, "<f>"
        assert_includes xml, "Summary &amp; Index"
        assert_includes xml, 'state="frozen"'
      end
    end
  end
end
