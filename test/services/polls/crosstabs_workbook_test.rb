require "test_helper"

class Polls::CrosstabsWorkbookTest < ActiveSupport::TestCase
  test "Excel opens with summary and index followed by numeric question sheets" do
    poll = Poll.create!(slug: "workbook", survey_slug: "survey", title_en: "Opinion poll", published_at: Time.zone.parse("2026-09-06"))
    table = { id: "duplicate/invalid:sheet-name", type: "multiple", question: { en: "=Dangerous label", fr: "Question française" },
      columns: [ { key: "all", label: { en: "Total" } }, { key: "missing", breakdownId: "qx5-income", label: { en: "Missing", fr: "Manquant" } }, { key: "age:unknown", id: "unknown", label: { en: "Unknown" } }, { key: "gender:unknown", label: { en: "Not recorded" } } ],
      rows: [ { label: { en: "Weighted sample size" }, kind: "unweighted-sample-size", values: { all: 100, missing: nil } },
        { label: { en: "Support", fr: "Pour" }, kind: "weighted-percent", values: { all: 67, missing: nil } },
        { label: { en: "Oppose", fr: "Contre" }, kind: "weighted-percent", values: { all: 0, missing: nil } } ] }
    report = { schemaVersion: 2, survey: { slug: "survey" }, breakdowns: [ { id: "qx5-income", label: { en: "What is your household income?", fr: "Revenu du ménage" } } ], warnings: [ "Internal warning" ], translationFallbacks: [ "internal.translation.key" ], tables: [ table, table ], weighting: { method: "none", unweightedResponses: 100 } }
    poll.crosstabs_json.attach(io: StringIO.new(report.to_json), filename: "tabs.json", content_type: "application/json", identify: false)
    bytes = Polls::CrosstabsWorkbook.new(poll).render
    Tempfile.create([ "crosstabs", ".xlsx" ]) do |file|
      file.binmode; file.write(bytes); file.flush
      workbook = Roo::Excelx.new(file.path)
      assert_equal [ "Summary & Index", "Q1", "Q2" ], workbook.sheets
      assert_equal "Build Canada\nOpinion poll", workbook.sheet(0).cell(1, 1)
      assert_equal "September 6, 2026", workbook.sheet(0).cell(2, 2)
      assert_includes workbook.sheet(1).cell(2, 1), "=Dangerous label"
      [ "Q1", "Q2" ].each do |name|
        sheet = workbook.sheet(name)
        assert_includes sheet.cell(2, 1), "Question française"
        assert_equal "Support\nPour", sheet.cell(5, 1)
        assert_equal "Oppose\nContre", sheet.cell(6, 1)
      end
      assert_equal 67, workbook.sheet(1).cell(5, 2)
      assert_equal 0, workbook.sheet(1).cell(6, 2)
      assert_equal "Suppressed", workbook.sheet(1).cell(5, 3)
      assert_equal 3, workbook.sheet(1).last_column
      assert_equal "Household income\nMissing", workbook.sheet(1).cell(3, 3)
      assert_equal 2, workbook.sheet(0).last_column
      all_text = workbook.sheets.flat_map { |name| workbook.sheet(name).to_a.flatten }.compact.join("\n")
      [ table[:id], "Question ID", "Question type", "Breakdown semantics", "Translation fallback", "Internal warning", "internal.translation.key", "Not recorded", "Manquant", "Revenu du ménage", "What is your household income?" ].each do |internal|
        assert_not_includes all_text, internal
      end
      assert_not_includes workbook.sheet(1).to_a.flatten, "Unknown"
      assert_not_includes workbook.sheet(0).to_a.flatten, "Survey"

      Zip::File.open(file.path) do |zip|
        zip.each do |entry|
          next unless entry.name.end_with?(".xml", ".rels")
          Nokogiri::XML(entry.get_input_stream.read) { |config| config.strict.nonet }
        end
        assert_equal "A1:B1", Nokogiri::XML(zip.read("xl/worksheets/sheet1.xml")).at_xpath("//*[local-name()='mergeCell']")["ref"]
        styles = Nokogiri::XML(zip.read("xl/styles.xml"))
        assert_includes styles.xpath("//*[local-name()='numFmt']/@formatCode").map(&:value), '0\%'
        xml = zip.read("xl/worksheets/sheet2.xml")
        assert_not_includes xml, "<f>"
        assert_includes xml, "Summary &amp; Index"
        assert_includes xml, 'state="frozen"'
        assert_includes xml, 'showGridLines="0"'
        assert_equal "A2:C2", Nokogiri::XML(xml).at_xpath("//*[local-name()='mergeCell']")["ref"]
        assert_includes zip.read("xl/styles.xml"), "F3E7DC"
      end
    end
  end

  test "arm sections have independent numeric results and suppressed sample sizes" do
    columns = [ { key: "overall:all", id: "all", breakdownId: "overall", label: { en: "Total" } },
      { key: "age:young", id: "young", breakdownId: "age", label: { en: "18–34" } } ]
    rows = ->(total, young, percent) { [
      { id: "base", kind: "unweighted-sample-size", label: { en: "Sample size" }, values: { "overall:all" => total, "age:young" => young } },
      { id: "weighted", kind: "weighted-sample-size", label: { en: "Weighted sample size" }, values: { "overall:all" => 500, "age:young" => 200 } },
      { id: "yes", kind: "weighted-percent", label: { en: "Yes", fr: "Oui" }, values: { "overall:all" => percent, "age:young" => 0 } }
    ] }
    table = { id: "q1", question: { en: "Choose an option" }, columns: columns, rows: rows.call(400, 199, 55), arms: [
      { id: "internal-a", question: { en: "First wording", fr: "Première version" }, columns: columns, rows: rows.call(200, 50, 70) },
      { id: "internal-b", question: { en: "Second wording" }, columns: columns, rows: rows.call(200, 49, 40) }
    ] }
    upload = Struct.new(:download).new({ schemaVersion: 2, tables: [ table ] }.to_json)
    poll = Struct.new(:crosstabs_json, :title_en, :published_at).new(upload, "Survey", nil)
    Tempfile.create([ "versions", ".xlsx" ]) do |file|
      file.binmode; file.write(Polls::CrosstabsWorkbook.new(poll).render); file.flush
      sheet = Roo::Excelx.new(file.path).sheet("Q1")
      first = sheet.to_a.index { |row| row[0] == "Version 1: First wording\nPremière version" } + 1
      second = sheet.to_a.index { |row| row[0] == "Version 2: Second wording" } + 1
      assert_equal 200, sheet.cell(first + 1, 2)
      assert_equal 50, sheet.cell(first + 1, 3)
      assert_equal "Yes\nOui", sheet.cell(first + 3, 1)
      assert_equal 70, sheet.cell(first + 3, 2)
      assert_equal 0, sheet.cell(first + 3, 3)
      assert_equal 40, sheet.cell(second + 3, 2)
      assert_equal "Suppressed", sheet.cell(second + 1, 3)
      assert_equal "Suppressed", sheet.cell(second + 2, 3)
      assert_equal "Suppressed", sheet.cell(second + 3, 3)
      assert_not_includes sheet.to_a.flatten.join, "internal-a"
      assert_includes sheet.to_a.flatten.join, "Première version"
    end
  end
  test "split ballot labels stay associated with their version" do
    variants = { "a" => { en: "Keep it", fr: "Conserver" }, "b" => { en: "Replace it", fr: "Remplacer" } }
    columns = [ { key: "all", label: { en: "Total" } } ]
    rows = [ { kind: "unweighted-sample-size", label: { en: "Sample size" }, values: { all: 100 } },
      { kind: "weighted-percent", label: { en: "Choice", fr: "Choix" }, armVariants: variants, values: { all: 60 } } ]
    table = { id: "q1", question: { en: "Question" }, columns: columns, rows: rows,
      arms: variants.keys.map { |id| { id: id, question: { en: "Wording #{id}" }, columns: columns, rows: rows } } }
    upload = Struct.new(:download).new({ schemaVersion: 2, tables: [ table ] }.to_json)
    poll = Struct.new(:crosstabs_json, :title_en, :published_at).new(upload, "Survey", nil)
    Tempfile.create([ "arm-labels", ".xlsx" ]) do |file|
      file.binmode; file.write(Polls::CrosstabsWorkbook.new(poll).render); file.flush
      sheet = Roo::Excelx.new(file.path).sheet("Q1").to_a
      assert_includes sheet, [ "Choice\nChoix", 60 ]
      assert_includes sheet.map(&:first), "Version 1: Keep it\nConserver"
      assert_includes sheet.map(&:first), "Version 2: Replace it\nRemplacer"
      first = sheet.index { |row| row.first == "Version 1: Wording a" }
      second = sheet.index { |row| row.first == "Version 2: Wording b" }
      assert_equal [ "Keep it\nConserver", 60 ], sheet[first + 2]
      assert_equal [ "Replace it\nRemplacer", 60 ], sheet[second + 2]
      assert_not_includes sheet[first...second].flatten.join, "Remplacer"
      assert_not_includes sheet[second..].flatten.join, "Conserver"
    end
  end

  test "dependent tables get their own sheets, numbered after their question, with index links" do
    columns = ->(*keys) { [ { key: "overall:all", id: "all", breakdownId: "overall", label: { en: "Total" } },
      *keys.map { |key| { key: key, id: key.split(":").last, breakdownId: key.split(":").first, label: { en: key.split(":").last.titleize } } } ] }
    row = ->(label, kind, values) { { kind: kind, label: { en: label }, values: values } }
    posture = { id: "q2-posture", question: { en: "Hold firm or concede?" }, columns: columns.call("age:young"),
      rows: [ row.call("Sample size", "unweighted-sample-size", { "overall:all" => 400, "age:young" => 150 }), row.call("Hold firm", "weighted-percent", { "overall:all" => 60, "age:young" => 55 }) ] }
    groceries = { id: "q4-groceries", question: { en: "Paying more for groceries" }, columns: columns.call("age:young"),
      rows: [ row.call("Sample size", "unweighted-sample-size", { "overall:all" => 400, "age:young" => 150 }), row.call("Acceptable", "weighted-percent", { "overall:all" => 40, "age:young" => 30 }) ] }
    dependent = { id: "q4-groceries", question: { en: "Paying more for groceries" }, columns: columns.call("q2-posture:hold-firm", "q2-posture:concede", "q2-posture:unknown"),
      rows: [ row.call("Sample size", "unweighted-sample-size", { "overall:all" => 400, "q2-posture:hold-firm" => 50, "q2-posture:concede" => 49, "q2-posture:unknown" => 0 }),
        row.call("Acceptable", "weighted-percent", { "overall:all" => 40, "q2-posture:hold-firm" => 58, "q2-posture:concede" => 13, "q2-posture:unknown" => nil }) ] }
    report = { schemaVersion: 2, tables: [ posture, groceries ], dependentTables: [ dependent ], breakdowns: [
      { id: "overall", kind: "overall", label: { en: "Overall" } }, { id: "age", kind: "census", label: { en: "Age" } },
      { id: "q2-posture", kind: "question", label: { en: "Hold firm or concede?" } } ] }
    upload = Struct.new(:download).new(report.to_json)
    poll = Struct.new(:crosstabs_json, :title_en, :published_at).new(upload, "Survey", nil)
    Tempfile.create([ "dependent", ".xlsx" ]) do |file|
      file.binmode; file.write(Polls::CrosstabsWorkbook.new(poll).render); file.flush
      workbook = Roo::Excelx.new(file.path)
      assert_equal [ "Summary & Index", "Q1", "Q2", "Q2 by others" ], workbook.sheets
      index = workbook.sheet("Summary & Index").to_a
      assert_includes index.map(&:first), "By other questions"
      assert_equal [ "Question 2 by other questions", "Paying more for groceries" ], index.last
      assert_includes index.find { |row| row.first == "Reading the results" }.last, "by others"
      sheet = workbook.sheet("Q2 by others")
      assert_equal "Question 2 by other questions\nPaying more for groceries", sheet.cell(2, 1)
      assert_equal [ "Answer / sample size", "Total", "Q1: Hold firm or concede?\nHold Firm", "Q1: Hold firm or concede?\nConcede" ], sheet.row(3)
      assert_equal 58, sheet.cell(5, 3)
      assert_equal "Suppressed", sheet.cell(5, 4)
      assert_equal "Suppressed", sheet.cell(4, 4)
      assert_equal 50, sheet.cell(4, 3)
      assert_equal 4, sheet.last_column
      assert_equal "Age\nYoung", workbook.sheet("Q2").cell(3, 3)
      Zip::File.open(file.path) do |zip|
        assert_includes zip.read("xl/worksheets/sheet1.xml"), "&apos;Q2 by others&apos;!A1"
      end
    end
  end
end
