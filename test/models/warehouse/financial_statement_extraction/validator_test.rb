require "test_helper"

class Warehouse::FinancialStatementExtraction::ValidatorTest < ActiveSupport::TestCase
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

  def page_texts
    {
      1 => "Financial assets 100,000 Liabilities 60,000 Net financial assets 40,000 Non-financial assets 160,000 Accumulated surplus 200,000",
      2 => "Accumulated surplus, beginning 190,000 Total revenue 80,000 Total expenses 70,000 Annual surplus 10,000"
    }
  end
end
