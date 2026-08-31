require "test_helper"

class Warehouse::FinancialStatementExtraction::OcrTextCacheTest < ActiveSupport::TestCase
  setup { Warehouse::FinancialStatementExtraction::OcrTextCache.reset_statistics! }

  test "reuses exact content-addressed OCR text and reports cumulative hits" do
    Dir.mktmpdir do |directory|
      source = Pathname(directory).join("source.pdf")
      source.write("immutable pdf bytes")
      root = Pathname(directory).join("cache")
      events = []
      reporter = ->(event) { events << event }
      calls = 0
      options = { dpi: 300, preprocessing: { psm: 6 } }

      first = build_cache(root:, source:, reporter:).fetch(page: 7, mode: "table", options:) do
        calls += 1
        "table text\n"
      end
      second = build_cache(root:, source:, reporter:).fetch(page: 7, mode: "table", options:) do
        flunk "a cache hit must not run OCR"
      end

      assert_equal "table text\n", first
      assert_equal first, second
      assert_equal 1, calls
      assert_equal %w[miss hit], events.pluck(:ocr_cache)
      assert_equal({ "miss" => 1 }, events.first.fetch(:counts))
      assert_equal({ "miss" => 1, "hit" => 1 }, events.second.fetch(:counts))
    end
  end

  test "separates source content page mode and OCR options" do
    Dir.mktmpdir do |directory|
      root = Pathname(directory).join("cache")
      source_a = Pathname(directory).join("a.pdf").tap { _1.write("asset a") }
      source_b = Pathname(directory).join("b.pdf").tap { _1.write("asset b") }
      calls = 0
      fetch = lambda do |source:, page:, mode:, dpi:|
        build_cache(root:, source:).fetch(page:, mode:, options: { dpi: }) do
          calls += 1
          "result #{calls}"
        end
      end

      assert_equal "result 1", fetch.call(source: source_a, page: 1, mode: "plain", dpi: 300)
      assert_equal "result 2", fetch.call(source: source_b, page: 1, mode: "plain", dpi: 300)
      assert_equal "result 3", fetch.call(source: source_a, page: 2, mode: "plain", dpi: 300)
      assert_equal "result 4", fetch.call(source: source_a, page: 1, mode: "table", dpi: 300)
      assert_equal "result 5", fetch.call(source: source_a, page: 1, mode: "plain", dpi: 400)
      assert_equal 5, calls
    end
  end

  test "ignores a corrupted entry and atomically replaces it" do
    Dir.mktmpdir do |directory|
      source = Pathname(directory).join("source.pdf").tap { _1.write("asset") }
      root = Pathname(directory).join("cache")
      cache = build_cache(root:, source:)
      assert_equal "first", cache.fetch(page: 1, mode: "plain", options: {}) { "first" }
      entry = root.glob("*/*.json").sole
      entry.write("not json")

      calls = 0
      result = build_cache(root:, source:).fetch(page: 1, mode: "plain", options: {}) do
        calls += 1
        "recomputed"
      end

      assert_equal "recomputed", result
      assert_equal 1, calls
      assert_equal "recomputed", JSON.parse(entry.read).fetch("text")
    end
  end

  test "does not cache failed OCR" do
    Dir.mktmpdir do |directory|
      source = Pathname(directory).join("source.pdf").tap { _1.write("asset") }
      root = Pathname(directory).join("cache")
      cache = build_cache(root:, source:)

      assert_raises(Errno::ENOENT) do
        cache.fetch(page: 1, mode: "plain", options: {}) { raise Errno::ENOENT, "tesseract" }
      end
      assert_empty root.glob("*/*.json")
    end
  end

  test "concurrent callers compute once and leave one valid entry" do
    Dir.mktmpdir do |directory|
      source = Pathname(directory).join("source.pdf").tap { _1.write("asset") }
      root = Pathname(directory).join("cache")
      calls = 0
      mutex = Mutex.new
      start = Queue.new
      results = Queue.new
      workers = 2.times.map do
        Thread.new do
          start.pop
          result = build_cache(root:, source:).fetch(page: 9, mode: "table", options: { dpi: 300 }) do
            mutex.synchronize { calls += 1 }
            sleep 0.05
            "shared result"
          end
          results << result
        end
      end
      2.times { start << true }
      workers.each(&:join)

      assert_equal [ "shared result", "shared result" ], 2.times.map { results.pop }.sort
      assert_equal 1, calls
      assert_equal 1, root.glob("*/*.json").length
      assert_equal "shared result", JSON.parse(root.glob("*/*.json").sole.read).fetch("text")
    end
  end

  private

  def build_cache(root:, source:, reporter: ->(_event) { })
    Warehouse::FinancialStatementExtraction::OcrTextCache.new(root:, source_path: source, reporter:)
  end
end
