require "test_helper"

class Warehouse::FinancialStatementExtraction::ValidatorTest < ActiveSupport::TestCase
  test "accepts other comprehensive loss as rollforward evidence" do
    texts = page_texts.merge(
      2 => page_texts.fetch(2) + " Subsidiary operations - other comprehensive (loss) income"
    )
    validator = Validator.new(
      facts: clean_facts, fiscal_year: 2025, page_texts: texts,
      flags: { rollforward_adjustment_present: true }
    )

    check = validator.validate.find { |row| row[:id] == "exception_evidence:rollforward_adjustment_present" }

    assert_equal "pass", check[:status]
  end

  test "ignores a declared rollforward adjustment when no opening balance was extracted" do
    facts = clean_facts.reject { _1[:concept] == "opening_accumulated_surplus" }
    validator = Validator.new(
      facts:, fiscal_year: 2025, page_texts: page_texts,
      flags: { rollforward_adjustment_present: true }
    )
    checks = validator.validate
    flag_check = checks.find do |check|
      check[:id] == "exception_evidence:rollforward_adjustment_present"
    end

    assert validator.acceptable?(checks)
    assert_equal "pass", flag_check.fetch(:status)
    assert_equal "inactive", flag_check.fetch(:detail)
  end

  Validator = Warehouse::FinancialStatementExtraction::Validator

  test "accepts a complete internally consistent extraction" do
    validator = Validator.new(facts: clean_facts, fiscal_year: 2025, population: 100_000, page_texts: page_texts)
    checks = validator.validate

    assert validator.acceptable?(checks)
    assert checks.none? { |check| check[:status] == "fail" }
  end

  test "detects an operations digit error" do
    facts = clean_facts.map(&:dup)
    revenue = facts.find { |fact| fact[:concept] == "total_revenue" }
    revenue[:raw_text] = "81,000"
    revenue[:value] = BigDecimal("81000000")
    validator = Validator.new(facts:, fiscal_year: 2025, page_texts: page_texts.merge(2 => page_texts.fetch(2).sub("80,000", "81,000")))
    checks = validator.validate

    refute validator.acceptable?(checks)
    failure = checks.find { |check| check[:id] == "operations_surplus" }
    assert_equal "fail", failure[:status]
    assert_includes failure[:detail], "likely="
  end

  test "rejects a budget or comparative column" do
    facts = clean_facts.map(&:dup)
    facts.first[:column_year] = "Budget 2025"
    validator = Validator.new(facts:, fiscal_year: 2025, page_texts: page_texts)

    refute validator.acceptable?
    assert_equal "fail", validator.validate.find { |check| check[:id].start_with?("column_year:") }[:status]
  end

  test "missing concepts cannot pass through skipped identities" do
    validator = Validator.new(facts: [ clean_facts.first ], fiscal_year: 2025, page_texts: page_texts)

    refute validator.acceptable?
    assert_equal "fail", validator.validate.find { |check| check[:id] == "required_concepts" }[:status]
  end

  test "skips the operations identity only when separate mediating items are declared" do
    facts = clean_facts.map(&:dup)
    annual = facts.find { |fact| fact[:concept] == "annual_surplus" }
    annual[:raw_text] = "15,000"
    annual[:value] = BigDecimal("15000000")
    validator = Validator.new(
      facts:, fiscal_year: 2025,
      page_texts: page_texts.merge(2 => page_texts.fetch(2).sub("10,000", "15,000") + " Other contributions 5,000 Adjustment"),
      flags: { operations_adjustment_present: true, rollforward_adjustment_present: true }
    )
    checks = validator.validate

    assert validator.acceptable?(checks)
    assert_equal "skip", checks.find { |check| check[:id] == "operations_surplus" }.fetch(:status)
  end

  test "accepts source-backed single components when the position identity passes" do
    validator = Validator.new(
      facts: clean_facts, fiscal_year: 2025, page_texts: page_texts,
      flags: { single_component_concepts: %w[total_financial_assets total_non_financial_assets] }
    )
    checks = validator.validate

    assert validator.acceptable?(checks)
    assert_equal "pass", checks.find { _1[:id] == "position_single_component" }.fetch(:status)
  end

  test "rejects single components when remeasurement skips the position surplus identity" do
    facts = clean_facts.map(&:dup)
    accumulated = facts.find { _1[:concept] == "accumulated_surplus" }
    accumulated[:raw_text] = "201,000"
    accumulated[:value] = BigDecimal("201000000")
    texts = page_texts.merge(
      1 => page_texts.fetch(1).sub("200,000", "201,000") + " Accumulated remeasurement gains"
    )
    validator = Validator.new(
      facts:, fiscal_year: 2025, page_texts: texts,
      flags: {
        remeasurement_present: true,
        single_component_concepts: %w[total_financial_assets total_non_financial_assets]
      }
    )
    checks = validator.validate

    refute validator.acceptable?(checks)
    assert_equal "skip", checks.find { _1[:id] == "position_surplus" }.fetch(:status)
    assert_equal "fail", checks.find { _1[:id] == "position_single_component" }.fetch(:status)
  end

  test "requires detailed revenue and expense leaves to reconcile to headline totals" do
    line_items = [
      line_item("revenue", "Taxes", "Property taxes", "50,000", 50_000_000, 0),
      line_item("revenue", "Transfers", "Government transfers (Note 1)", "30,000", 30_000_000, 1),
      line_item("expense", "Services", "Operations", "70,000", 70_000_000, 0)
    ]
    text = page_texts.merge(
      3 => "Property taxes 50,000 Government transfers 2024 30,000 2025 (Note 1) Operations 70,000"
    )
    validator = Validator.new(facts: clean_facts, line_items:, fiscal_year: 2025, page_texts: text)

    assert validator.acceptable?
    line_sum_statuses = validator.validate.filter_map do |check|
      check[:status] if check[:id].start_with?("line_sum:")
    end
    assert_equal %w[pass pass], line_sum_statuses

    line_items.first[:value] = BigDecimal("40000000")
    refute Validator.new(facts: clean_facts, line_items:, fiscal_year: 2025, page_texts: text).acceptable?
  end

  test "reconciles detailed revenue including separately presented adjustments" do
    facts = clean_facts.map(&:dup)
    annual = facts.find { |fact| fact[:concept] == "annual_surplus" }
    annual[:raw_text] = "20,000"
    annual[:value] = BigDecimal("20000000")
    line_items = [
      line_item("revenue", "Revenue", "Operating revenue", "80,000", 80_000_000, 0),
      line_item("revenue", "Other", "Capital contributions", "10,000", 10_000_000, 1),
      line_item("expense", "Services", "Operations", "70,000", 70_000_000, 0)
    ]
    text = page_texts.merge(
      2 => page_texts.fetch(2).sub("10,000", "20,000") + " Other contributions Adjustment",
      3 => "Operating revenue 80,000 Capital contributions 10,000 Operations 70,000"
    )
    validator = Validator.new(
      facts:, line_items:, fiscal_year: 2025, page_texts: text,
      flags: { operations_adjustment_present: true, rollforward_adjustment_present: true }
    )

    assert_equal "pass", validator.validate.find { |check| check[:id] == "line_sum:revenue" }.fetch(:status)
  end

  test "prefers the printed revenue total when it already includes the adjustment" do
    facts = clean_facts.map(&:dup)
    annual = facts.find { |fact| fact[:concept] == "annual_surplus" }
    annual[:raw_text] = "15,000"
    annual[:value] = BigDecimal("15000000")
    line_items = [
      line_item("revenue", "Revenue", "Revenue including contributions", "80,000", 80_000_000, 0),
      line_item("expense", "Services", "Operations", "70,000", 70_000_000, 0)
    ]
    text = page_texts.merge(
      2 => page_texts.fetch(2).sub("10,000", "15,000") + " Capital contributions Adjustment",
      3 => "Revenue including contributions 80,000 Operations 70,000"
    )
    validator = Validator.new(
      facts:, line_items:, fiscal_year: 2025, page_texts: text,
      flags: { operations_adjustment_present: true, rollforward_adjustment_present: true }
    )

    check = validator.validate.find { _1[:id] == "line_sum:revenue" }
    assert_equal "pass", check.fetch(:status)
    assert_includes check.fetch(:detail), "headline=80000000.0"
  end

  private

  def clean_facts
    [
      fact("total_financial_assets", "Financial assets", "100,000", 100_000_000, "financial_position", 1),
      fact("total_liabilities", "Liabilities", "60,000", 60_000_000, "financial_position", 1),
      fact("net_financial_assets", "Net financial assets", "40,000", 40_000_000, "financial_position", 1),
      fact("total_non_financial_assets", "Non-financial assets", "160,000", 160_000_000, "financial_position", 1),
      fact("accumulated_surplus", "Accumulated surplus", "200,000", 200_000_000, "financial_position", 1),
      fact("opening_accumulated_surplus", "Accumulated surplus, beginning", "190,000", 190_000_000, "accumulated_surplus", 2),
      fact("total_revenue", "Total revenue", "80,000", 80_000_000, "operations", 2),
      fact("total_expenses", "Total expenses", "70,000", 70_000_000, "operations", 2),
      fact("annual_surplus", "Annual surplus", "10,000", 10_000_000, "operations", 2)
    ]
  end

  def fact(concept, raw_label, raw_text, value, statement, source_page)
    {
      concept:, raw_label:, raw_text:, value: BigDecimal(value.to_s), scale: 1_000,
      statement:, source_page:, column_year: "Actual 2025", extraction_confidence: BigDecimal("0.95")
    }
  end

  def line_item(flow, category, label, raw_text, value, position)
    {
      flow:, category:, label:, raw_text:, value: BigDecimal(value.to_s), scale: 1_000,
      source_page: 3, column_year: "Actual 2025", position:,
      extraction_confidence: BigDecimal("0.95")
    }
  end

  def page_texts
    {
      1 => "Financial assets 100,000 Liabilities 60,000 Net financial assets 40,000 Non-financial assets 160,000 Accumulated surplus 200,000",
      2 => "Accumulated surplus, beginning 190,000 Total revenue 80,000 Total expenses 70,000 Annual surplus 10,000"
    }
  end
end
