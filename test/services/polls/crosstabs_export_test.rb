require "test_helper"

class Polls::CrosstabsExportTest < ActiveSupport::TestCase
  def source
    { schemaVersion: 2, weighting: { unweightedResponses: 500, margins: [ { unknownResponses: 6 } ] },
      tables: [ { id: "q", columns: [
        { key: "overall:all", id: "all", breakdownId: "overall", label: "Total" },
        { key: "arm:a", id: "a", breakdownId: "arm", label: "A" },
        { key: "arm:b", id: "b", breakdownId: "arm", label: "B" }
      ], armVariants: { a: { en: "First wording" }, b: { en: "Second wording" } }, rows: [
        { id: "base", kind: "unweighted-sample-size", values: { "overall:all" => 500, "arm:a" => 50, "arm:b" => 49 } },
        { id: "weighted", kind: "weighted-sample-size", values: { "overall:all" => 600, "arm:a" => 200, "arm:b" => 300 } },
        { id: "yes", kind: "weighted-percent", label: { en: "Yes" }, values: { "overall:all" => 50, "arm:a" => 0, "arm:b" => 25 } }
      ] } ] }
  end

  test "legacy arm totals become independent rows without invented demographics" do
    report = Polls::CrosstabsExport.new(source.to_json).render
    arms = report.dig("tables", 0, "arms")
    assert_equal 2, arms.size
    assert_equal "First wording", arms[0].dig("question", "en")
    assert_equal 50, arms[0].dig("rows", 0, "values", "overall:all")
    assert_equal 0, arms[0].dig("rows", 2, "values", "overall:all")
    assert_equal [ "overall:all" ], arms[1]["suppressedColumns"]
    assert arms[1]["rows"].all? { |row| row["values"].values.all?(&:nil?) }
    assert_not report["weighting"].key?("margins")
    assert_equal report, Polls::CrosstabsExport.new(report.to_json).render
  end

  test "missing and zero unweighted bases fail closed rather than using weighted bases" do
    [ nil, 0, 49 ].each do |base|
      raw = source
      raw[:tables][0][:rows][0][:values]["overall:all"] = base
      report = Polls::CrosstabsExport.new(raw.to_json).render
      assert report["tables"][0]["rows"].all? { |row| row["values"]["overall:all"].nil? }
    end
    raw = source
    raw[:tables][0][:rows].shift
    report = Polls::CrosstabsExport.new(raw.to_json).render
    assert report["tables"][0]["rows"].all? { |row| row["values"].values.all?(&:nil?) }
  end

  test "rejects invalid schema rather than returning the original upload" do
    assert_raises(ArgumentError) { Polls::CrosstabsExport.new('{"schemaVersion":1}').render }
  end
end
