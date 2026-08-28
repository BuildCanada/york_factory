require "test_helper"

class Warehouse::FinancialStatementExtraction::PageLocatorTest < ActiveSupport::TestCase
  test "selects the first primary statements after the auditor report" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    pages = {
      1 => "Contents\nConsolidated Statement of Financial Position 5\nConsolidated Statement of Operations 6",
      3 => "Independent Auditors' Report\nWe audited the consolidated statement of financial position and statement of operations.",
      5 => "City\nConsolidated Statement of Financial Position\n2025 2024\nFinancial assets 100 90\nLiabilities 60 55",
      6 => "City\nConsolidated Statement of Operations\nand Accumulated Surplus\nActual 2025 Actual 2024\nRevenue 80 75",
      20 => "Notes to Consolidated Financial Statements\nThe statement of financial position includes many numbers 1 2 3 4 5 6 7 8 9",
      30 => "Trust Funds - Consolidated Statement of Financial Position\n100 90 80 70 60 50"
    }

    assert_equal 5, locator.send(:locate_page, pages, :position)
    assert_equal 6, locator.send(:locate_page, pages, :operations)
  end
end
