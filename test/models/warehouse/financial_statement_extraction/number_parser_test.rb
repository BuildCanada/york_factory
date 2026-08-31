require "test_helper"

class Warehouse::FinancialStatementExtraction::NumberParserTest < ActiveSupport::TestCase
  Parser = Warehouse::FinancialStatementExtraction::NumberParser

  test "parses English and French thousands separators" do
    assert_equal BigDecimal("1234567"), Parser.parse("1,234,567")
    assert_equal BigDecimal("1234567"), Parser.parse("1 234 567")
    assert_equal BigDecimal("1234567.89"), Parser.parse("1\u202F234\u202F567,89")
    assert_equal BigDecimal("3281940"), Parser.parse("3.281,940")
    assert_equal BigDecimal("1661695"), Parser.parse("1,661.695")
    assert_equal BigDecimal("3281.94"), Parser.parse("3.281,94")
  end

  test "parses parentheses and explicit minus as negative" do
    assert_equal BigDecimal("-1234"), Parser.parse("(1,234)")
    assert_equal BigDecimal("-1234"), Parser.parse("$ (1,234)")
    assert_equal BigDecimal("-1234"), Parser.parse("- 1 234")
  end

  test "repairs an opening OCR brace only in an otherwise parenthetical numeric token" do
    assert_equal BigDecimal("-3900710"), Parser.parse("{3,900,710)")

    [ "{3,900,710", "3,900{710)", "{abc)", "{3,900,710}" ].each do |token|
      assert_raises(Parser::ParseError) { Parser.parse(token) }
    end
  end

  test "repairs one OCR quote inserted between valid thousands separators" do
    assert_equal BigDecimal("63121"), Parser.parse("63,',121")
    assert_equal BigDecimal("-63121"), Parser.parse("$ (63,’ ,121)")

    [ "6'3121", "63,'12", "63,',12", "value 63,',121", "1,23,',456" ].each do |token|
      assert_raises(Parser::ParseError) { Parser.parse(token) }
    end
  end

  test "repairs one OCR quote after a comma in a valid grouped integer" do
    assert_equal BigDecimal("20159"), Parser.parse("20,'159")
    assert_equal BigDecimal("-20159"), Parser.parse("$ (20,’159)")

    [ "20,'15", "20'159", "20,''159", "20,'1,159", "value 20,'159", "1,23,'456" ].each do |token|
      assert_raises(Parser::ParseError) { Parser.parse(token) }
    end
  end

  test "repairs a spaced OCR quote before a valid grouped integer" do
    assert_equal BigDecimal("344092"), Parser.parse("' 344,092")
    assert_equal BigDecimal("344092"), Parser.parse("’\u00A0344,092")

    [ "'344,092", "3'44,092", "' 344,09", "amount ' 344,092", "'", "’" ].each do |token|
      assert_raises(Parser::ParseError) { Parser.parse(token) }
    end
  end

  test "repairs one OCR period after a valid grouped integer" do
    assert_equal BigDecimal("11140886"), Parser.parse("11,140,886.")
    assert_equal BigDecimal("1234.50"), Parser.parse("1,234.50")

    [ "123.", "1,234..", "value 1,234.", "1,23,456." ].each do |token|
      assert_raises(Parser::ParseError) { Parser.parse(token) }
    end
  end

  test "repairs visually verified lowercase ell glyphs in a grouped integer" do
    assert_equal BigDecimal("11744"), Parser.parse("ll,744")
    assert_equal BigDecimal("11744000"), Parser.parse("ll,744,000")

    [ "l1,744", "I1,744", "ll744", "ll,74", "value ll,744" ].each do |token|
      assert_raises(Parser::ParseError) { Parser.parse(token) }
    end
  end

  test "normalizes a positive printed net debt to negative net financial assets" do
    assert_equal BigDecimal("-1234"), Parser.parse("1,234", raw_label: "Net debt", concept: "net_financial_assets")
    assert_equal BigDecimal("-1234"), Parser.parse("1 234", raw_label: "Dette nette", concept: "net_financial_assets")
  end

  test "keeps a combined net financial assets and net debt label positive when printed positive" do
    assert_equal BigDecimal("1234"), Parser.parse(
      "1 234", raw_label: "ACTIFS FINANCIERS NETS (DETTE NETTE)", concept: "net_financial_assets"
    )
  end

  test "normalizes positive printed deficits to negative surplus concepts" do
    assert_equal BigDecimal("-1250"), Parser.parse(
      "1 250", raw_label: "Déficit de l'exercice", concept: "annual_surplus"
    )
    assert_equal BigDecimal("-925"), Parser.parse(
      "925", raw_label: "Accumulated deficit", concept: "accumulated_surplus"
    )
  end

  test "does not negate a positive value when the label presents surplus and deficit alternatives" do
    assert_equal BigDecimal("1998"), Parser.parse(
      "1,998", raw_label: "ANNUAL (DEFICIT)/SURPLUS", concept: "annual_surplus"
    )
  end

  test "does not negate unaccented French excedent and deficit alternatives" do
    assert_equal BigDecimal("21684393"), Parser.parse(
      "21684393", raw_label: "EXCEDENT (DEFICIT) ACCUMULE", concept: "accumulated_surplus"
    )
    assert_equal BigDecimal("31445383"), Parser.parse(
      "31 445 383", raw_label: "EXCÉDENT (DÉFICIT) ACCUMULÉ", concept: "accumulated_surplus"
    )
  end

  test "does not conflate dash with zero" do
    [ "-", "‐", "‒", "–", "—", "−", "--", "---", "‒‒", "−−", "$ -", "$ ‒", "$ −", "$ --", "$ ---" ].each do |dash|
      assert Parser.null_marker?(dash), "expected #{dash.inspect} to be a null marker"
      assert_raises(Parser::ParseError) { Parser.parse(dash) }
    end
    [ "----", "1---2", "1‒2", "1−2", "−1,234", "value ‒", "value −" ].each do |token|
      refute Parser.null_marker?(token)
      assert_raises(Parser::ParseError) { Parser.parse(token) }
    end
    assert Parser.null_marker?("=")
    refute Parser.null_marker?("0")
    assert_equal BigDecimal("0"), Parser.parse("0")
  end

  test "does not treat embedded Unicode hyphens as null markers or numeric signs" do
    [ "1‐2", "‐123" ].each do |token|
      refute Parser.null_marker?(token)
      assert_raises(Parser::ParseError) { Parser.parse(token) }
    end
  end

  test "treats isolated OCR quote glyphs as null markers rather than numeric zero" do
    [ '"', "“", "”", "„", "‟", "″" ].each do |glyph|
      assert Parser.null_marker?(glyph), "expected #{glyph.inspect} to be a null marker"
      assert_raises(Parser::ParseError) { Parser.parse(glyph) }
    end
  end

  test "treats an isolated OCR period as a null marker without broad punctuation repair" do
    assert Parser.null_marker?(".")
    assert Parser.null_marker?(" . ")
    assert_raises(Parser::ParseError) { Parser.parse(".") }

    [ "..", "...", ".0", "0.", "value ." ].each do |token|
      refute Parser.null_marker?(token)
      assert_raises(Parser::ParseError) { Parser.parse(token) }
    end
  end
end
