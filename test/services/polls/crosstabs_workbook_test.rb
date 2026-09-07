require "test_helper"

class Polls::CrosstabsWorkbookTest < ActiveSupport::TestCase
  test "Excel opens with summary and index followed by numeric question sheets" do
    poll = Poll.create!(slug: "workbook", survey_slug: "survey", title_en: "Opinion poll", published_at: Time.zone.parse("2026-09-06"))
    table = { id: "duplicate/invalid:sheet-name", type: "multiple", question: { en: "=Dangerous label", fr: "Question française" },
      columns: [ { key: "all", label: { en: "Total" } }, { key: "missing", label: { en: "Missing" } }, { key: "age:unknown", id: "unknown", label: { en: "Unknown" } }, { key: "gender:unknown", label: { en: "Not recorded" } } ],
      rows: [ { label: { en: "Weighted sample size" }, kind: "weighted-sample-size", values: { all: 100, missing: nil } },
        { label: { en: "Support" }, kind: "weighted-percent", values: { all: 67, missing: nil } },
        { label: { en: "Oppose" }, kind: "weighted-percent", values: { all: 0, missing: nil } } ] }
    report = { schemaVersion: 2, survey: { slug: "survey" }, warnings: [ "Internal warning" ], translationFallbacks: [ "internal.translation.key" ], tables: [ table, table ], weighting: { method: "none", unweightedResponses: 100 } }
    poll.crosstabs_json.attach(io: StringIO.new(report.to_json), filename: "tabs.json", content_type: "application/json", identify: false)
    bytes = Polls::CrosstabsWorkbook.new(poll).render
    Tempfile.create([ "crosstabs", ".xlsx" ]) do |file|
      file.binmode; file.write(bytes); file.flush
      workbook = Roo::Excelx.new(file.path)
      assert_equal [ "Summary & Index", "Q1", "Q2" ], workbook.sheets
      assert_equal "Build Canada", workbook.sheet(0).cell(1, 1)
      assert_equal "Opinion poll", workbook.sheet(0).cell(1, 2)
      assert_equal "September 6, 2026", workbook.sheet(0).cell(2, 2)
      assert_includes workbook.sheet(1).cell(2, 2), "=Dangerous label"
      assert_equal 67, workbook.sheet(1).cell(5, 2)
      assert_equal 0, workbook.sheet(1).cell(6, 2)
      assert_nil workbook.sheet(1).cell(5, 3)
      assert_equal 3, workbook.sheet(1).last_column
      assert_equal 2, workbook.sheet(0).last_column
      all_text = workbook.sheets.flat_map { |name| workbook.sheet(name).to_a.flatten }.compact.join("\n")
      [ table[:id], "Question ID", "Question type", "Breakdown semantics", "Translation fallback", "Internal warning", "internal.translation.key", "Not recorded" ].each do |internal|
        assert_not_includes all_text, internal
      end
      assert_not_includes workbook.sheet(1).to_a.flatten, "Unknown"
      assert_not_includes workbook.sheet(0).to_a.flatten, "Survey"

      Zip::File.open(file.path) do |zip|
        zip.each do |entry|
          next unless entry.name.end_with?(".xml", ".rels")
          Nokogiri::XML(entry.get_input_stream.read) { |config| config.strict.nonet }
        end
        styles = Nokogiri::XML(zip.read("xl/styles.xml"))
        assert_includes styles.xpath("//*[local-name()='numFmt']/@formatCode").map(&:value), '0\%'
        xml = zip.read("xl/worksheets/sheet2.xml")
        assert_not_includes xml, "<f>"
        assert_includes xml, "Summary &amp; Index"
        assert_includes xml, 'state="frozen"'
        assert_includes xml, 'showGridLines="0"'
        assert_equal "B2:C2", Nokogiri::XML(xml).at_xpath("//*[local-name()='mergeCell']")["ref"]
        assert_includes zip.read("xl/styles.xml"), "F3E7DC"
      end
    end
  end

  test "wording versions preserve customer content without exposing internal arm or option identifiers" do
    table = { question: { en: "Choose an option" },
      variants: { "internal-arm" => { prompt: { en: "A different question" }, description: { en: "Read carefully" }, options: { "option-id" => { en: "Answer wording" } } } },
      columns: [ { key: "age:unknown", id: "unknown", label: { en: "Unknown" } }, { key: "all", label: { en: "Total" } } ],
      rows: [ { kind: "weighted-percent", label: { en: "Yes" }, armVariants: { "internal-arm" => { en: "Alternate answer" } }, values: { "age:unknown" => 25, all: 75 } } ] }
    upload = Struct.new(:download).new({ schemaVersion: 2, tables: [ table ] }.to_json)
    poll = Struct.new(:crosstabs_json, :title_en, :published_at).new(upload, "Survey", nil)
    Tempfile.create([ "versions", ".xlsx" ]) do |file|
      file.binmode; file.write(Polls::CrosstabsWorkbook.new(poll).render); file.flush
      sheet = Roo::Excelx.new(file.path).sheet("Q1")
      assert_equal "Version 1", sheet.cell(3, 1)
      assert_equal "A different question\nRead carefully\nAnswer wording", sheet.cell(3, 2)
      assert_equal 75, sheet.cell(5, 2)
      assert_equal "Version 1: Alternate answer", sheet.cell(6, 1)
      assert_equal 2, sheet.last_column
      assert_not_includes sheet.to_a.flatten.join, "internal-arm"
      assert_not_includes sheet.to_a.flatten.join, "option-id"
    end
  end
end
