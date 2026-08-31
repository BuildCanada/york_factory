require "test_helper"

class Warehouse::FinancialStatementExtraction::ScaleDetectorTest < ActiveSupport::TestCase
  test "detects explicit statement units" do
    detector = Warehouse::FinancialStatementExtraction::ScaleDetector

    assert_equal 1, detector.detect([ "Statement of Operations ($)" ])
    assert_equal 1_000, detector.detect([ "Statement of Operations (in thousands)" ])
    assert_equal 1_000, detector.detect([ "Amounts in $000's" ])
    assert_equal 1_000, detector.detect([ "Montants en milliers de dollars" ])
    assert_equal 1_000_000, detector.detect([ "CAD in millions" ])
  end

  test "prefers the statement's explicit units over a nearby chart's units" do
    text = "For the year ended December 31 (in thousands of dollars)\nIn millions"

    assert_equal 1_000, Warehouse::FinancialStatementExtraction::ScaleDetector.detect([ text ])
  end
end
