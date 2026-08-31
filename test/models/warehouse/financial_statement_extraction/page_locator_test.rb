require "test_helper"

class Warehouse::FinancialStatementExtraction::PageLocatorTest < ActiveSupport::TestCase
  test "shares exact table OCR through the persistent content cache" do
    Dir.mktmpdir do |directory|
      source = Pathname(directory).join("source.pdf").tap { _1.write("immutable pdf bytes") }
      cache_root = Pathname(directory).join("cache")
      calls = []
      first = Warehouse::FinancialStatementExtraction::PageLocator.new(
        source, ocr_cache_root: cache_root, ocr_cache_reporter: ->(_event) { }
      )
      first.define_singleton_method(:perform_table_ocr) do |page|
        calls << page
        "cached table OCR #{page}"
      end
      second = Warehouse::FinancialStatementExtraction::PageLocator.new(
        source, ocr_cache_root: cache_root, ocr_cache_reporter: ->(_event) { }
      )
      second.define_singleton_method(:perform_table_ocr) do |_page|
        flunk "persistent cache hit must not invoke OCR tools"
      end

      assert_equal "cached table OCR 7", first.ocr_table_page(7)
      assert_equal "cached table OCR 7", second.ocr_table_page(7)
      assert_equal [ 7 ], calls
    end
  end

  test "memoizes table OCR by physical page" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    calls = []
    locator.define_singleton_method(:perform_table_ocr) do |page|
      calls << page
      "table OCR #{page}"
    end

    assert_equal "table OCR 7", locator.ocr_table_page(7)
    assert_equal "table OCR 7", locator.ocr_table_page("7")
    assert_equal [ 7 ], calls
  end

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

  test "does not select wrapped auditor prose after an index mentions the auditor report" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    pages = {
      2 => "Contents\nIndependent Auditor's Report 1\nConsolidated Statement of Financial Position 3",
      4 => <<~TEXT,
        Independent Auditor's Report
        Opinion
        We audited the consolidated financial statements, which comprise the
        consolidated statement of financial position as at December 31, 2022.
      TEXT
      6 => <<~TEXT
        Municipality of Northern Village of Air Ronge
        Consolidated Statement of Financial Position
        As at December 31, 2022
        2022 2021
        Financial Assets 7,109,579 6,412,443
      TEXT
    }

    assert_equal 6, locator.send(:locate_page, pages, :position)
  end

  test "does not select an index page ahead of scanned primary statements" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    pages = {
      2 => <<~TEXT,
        City
        Index to the Consolidated Financial Statements
        Consolidated Statement of Financial Position
        Consolidated Statement of Financial Activities
        4 5 6 7 8 9
      TEXT
      4 => "City\nConsolidated Statement of Financial Position\n2025 2024\nAssets 100 90",
      5 => "City\nConsolidated Statement of Financial Activities\n2025 2024\nRevenue 80 75"
    }

    assert_equal 4, locator.send(:locate_page, pages, :position)
    assert_equal 5, locator.send(:locate_page, pages, :operations)
  end

  test "requests OCR instead of accepting an exhibit by-fund position statement" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    pages = {
      6 => "",
      7 => "City\nConsolidated Statement of Operations\n2025 2024\nRevenue 80 75",
      31 => <<~TEXT
        CITY OF EXAMPLE Exhibit 1
        Statement of Financial Position - By Fund
        2025 2024
        Financial assets 100 90
      TEXT
    }

    assert locator.send(:needs_ocr?, pages)

    pages[6] = <<~TEXT
      CITY OF EXAMPLE
      Consolidated Statement of Financial Position
      2025 2024
      FINANCIAL ASSETS
      Cash and cash equivalents (Note 2) 100 90
    TEXT
    assert_equal 6, locator.send(:locate_page, pages, :position)
  end

  test "does not treat French auditor prose as a primary statement heading" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    pages = {
      4 => "Village\nRAPPORT\nNous avons audité l'état de la situation financière et l'état des résultats.",
      7 => "Village\nÉTAT DES RÉSULTATS\nEXERCICE TERMINÉ LE 31 DÉCEMBRE 2023\n2023 2023 2022\nRevenus 1 10 9",
      8 => "Village\nÉTAT DE LA SITUATION FINANCIÈRE\nAU 31 DÉCEMBRE 2023\n2023 2022\nActifs 10 9"
    }

    assert_equal 7, locator.send(:locate_page, pages, :operations)
    assert_equal 8, locator.send(:locate_page, pages, :position)
  end

  test "requests OCR when only auditor prose identifies a blank primary statement" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    pages = {
      3 => "Independent Auditors' Report\nWe audited the consolidated statement of financial position.",
      5 => "",
      6 => "City\nConsolidated Statement of Operations\n2025 2024\nRevenue 80 75"
    }

    assert locator.send(:needs_ocr?, pages)
  end

  test "tolerates one short OCR noise token in a primary financial position title" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    pages = {
      2 => "Independent Auditors' Report\nWe audited the statement of financial PI position.",
      4 => "Town\nSTATEMENT OF FINANCIAL PI POSITION\n2011 2010\nFinancial assets 100 90",
      8 => "Notes to Financial Statements\nThe statement of financial PI position includes several estimates."
    }

    assert_equal 4, locator.send(:locate_page, pages, :position)
  end

  test "does not tolerate an unbounded OCR phrase in a financial position title" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    pages = {
      4 => "Town\nSTATEMENT OF FINANCIAL VERY NOISY POSITION\n2011 2010\nFinancial assets 100 90"
    }

    assert_nil locator.send(:locate_page, pages, :position)
  end

  test "recognizes malformed dense-table OCR numbers that need a layout retry" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")

    assert_equal 1, locator.send(:malformed_ocr_number_count, "Capital transfers 29,522.21]")
    assert_equal 0, locator.send(:malformed_ocr_number_count, "Capital transfers 29,522,211")
  end

  test "repairs single-space OCR digit fragments without merging spaced columns" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    text = "Net assets 494 468             556,508\nCapital 67.71 7               165,727\n"

    assert_equal "Net assets 494468             556,508\nCapital 67.717               165,727\n",
      locator.send(:normalize_table_ocr_digit_fragments, text)
  end

  test "repairs only bounded leading table OCR digit confusables" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    text = "Total L,747,384  I,234,567  l,111,222  1,747,384  AL,747,384  L,747\n"

    assert_equal "Total 1,747,384  1,234,567  1,111,222  1,747,384  AL,747,384  L,747\n",
      locator.send(:normalize_table_ocr_digit_fragments, text)
  end

  test "computes the inverse correction for rotated scanned pages" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    locator.instance_variable_set(:@page_rotation, 270)
    success = Object.new
    success.define_singleton_method(:success?) { true }

    capture = lambda do |*arguments|
      assert_equal [ "magick", "/tmp/source.png", "-rotate", "90", "/tmp/page-oriented.png" ], arguments
      [ "", "", success ]
    end
    Open3.stub(:capture3, capture) do
      result = locator.send(
        :correct_ocr_orientation, "/tmp/source.png", directory: "/tmp", name: "page"
      )

      assert_equal "/tmp/page-oriented.png", result
    end
  end

  test "does not rotate a landscape source that renders upright" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    locator.instance_variable_set(:@page_rotation, 90)
    locator.instance_variable_set(:@source_page_landscape, true)

    assert_equal "/tmp/source.png", locator.send(
      :correct_ocr_orientation, "/tmp/source.png", directory: "/tmp", name: "page"
    )
  end

  test "does not rotate a 180 degree source that pdftoppm renders upright" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator.new("unused.pdf")
    locator.instance_variable_set(:@page_rotation, 180)
    locator.instance_variable_set(:@source_page_landscape, false)

    Open3.stub(:capture3, ->(*) { flunk "ImageMagick should not be called" }) do
      assert_equal "/tmp/source.png", locator.send(
        :correct_ocr_orientation, "/tmp/source.png", directory: "/tmp", name: "page"
      )
    end
  end
end
