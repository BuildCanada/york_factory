require "test_helper"

class Warehouse::FinancialStatementExtraction::NumberParserTest < ActiveSupport::TestCase
  Parser = Warehouse::FinancialStatementExtraction::NumberParser

  test "parses English and French thousands separators" do
    assert_equal BigDecimal("1234567"), Parser.parse("1,234,567")
    assert_equal BigDecimal("1234567"), Parser.parse("1 234 567")
    assert_equal BigDecimal("1234567.89"), Parser.parse("1\u202F234\u202F567,89")
  end

  test "parses parentheses and explicit minus as negative" do
    assert_equal BigDecimal("-1234"), Parser.parse("(1,234)")
    assert_equal BigDecimal("-1234"), Parser.parse("- 1 234")
  end

  test "normalizes a positive printed net debt to negative net financial assets" do
    assert_equal BigDecimal("-1234"), Parser.parse("1,234", raw_label: "Net debt", concept: "net_financial_assets")
    assert_equal BigDecimal("-1234"), Parser.parse("1 234", raw_label: "Dette nette", concept: "net_financial_assets")
  end

  test "normalizes positive printed deficits to negative surplus concepts" do
    assert_equal BigDecimal("-1250"), Parser.parse(
      "1 250", raw_label: "Déficit de l'exercice", concept: "annual_surplus"
    )
    assert_equal BigDecimal("-925"), Parser.parse(
      "925", raw_label: "Accumulated deficit", concept: "accumulated_surplus"
    )
  end

  test "does not conflate dash with zero" do
    assert_raises(Parser::ParseError) { Parser.parse("—") }
    assert_equal BigDecimal("0"), Parser.parse("0")
  end
end
