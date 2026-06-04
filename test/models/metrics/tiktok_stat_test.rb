require "test_helper"

module Metrics
  class TiktokStatTest < ActiveSupport::TestCase
    CSV_WITH_BOM = "\uFEFF\"Date\",\"Video Views\",\"Profile Views\",\"Likes\",\"Comments\",\"Shares\"\n" \
      "\"April 4\",\"641\",\"15\",\"27\",\"2\",\"2\"\n" \
      "\"April 5\",\"754\",\"15\",\"29\",\"0\",\"1\"\n"

    test "upsert_from_csv imports rows" do
      result = TiktokStat.upsert_from_csv("build_canada", CSV_WITH_BOM, start_year: 2026)

      assert_equal 2, result[:inserted]
      assert_equal 0, result[:updated]
      assert_empty result[:errors]

      stat = TiktokStat.find_by!(account: "build_canada", date: Date.new(2026, 4, 4))
      assert_equal 641, stat.video_views
      assert_equal 15, stat.profile_views
      assert_equal 27, stat.likes
    end

    test "upsert_from_csv handles binary-encoded content with BOM from zip extraction" do
      binary_content = CSV_WITH_BOM.dup.force_encoding(Encoding::ASCII_8BIT)
      result = TiktokStat.upsert_from_csv("build_canada", binary_content, start_year: 2026)

      assert_equal 2, result[:inserted]
      assert_empty result[:errors]
    end

    test "upsert_from_csv rejects rows with corrupted metric values instead of coercing them" do
      corrupted = "\"Date\",\"Video Views\",\"Profile Views\",\"Likes\",\"Comments\",\"Shares\"\n" \
        "\"April 4\",\"641\xFF\",\"15\",\"27\",\"2\",\"2\"\n" \
        "\"April 5\",\"754\",\"15\",\"29\",\"0\",\"1\"\n"
      corrupted.force_encoding(Encoding::ASCII_8BIT)

      result = TiktokStat.upsert_from_csv("build_canada", corrupted, start_year: 2026)

      assert_equal 1, result[:inserted]
      assert_equal 1, result[:errors].size
      assert_match(/Video Views/, result[:errors].first)
      assert_not TiktokStat.exists?(account: "build_canada", date: Date.new(2026, 4, 4))
      assert TiktokStat.exists?(account: "build_canada", date: Date.new(2026, 4, 5))
    end

    test "upsert_from_csv reports unparseable dates as row errors instead of raising" do
      csv = "\"Date\",\"Video Views\",\"Profile Views\",\"Likes\",\"Comments\",\"Shares\"\n" \
        "\"Notamonth 4\",\"641\",\"15\",\"27\",\"2\",\"2\"\n" \
        "\"April 5\",\"754\",\"15\",\"29\",\"0\",\"1\"\n"

      result = TiktokStat.upsert_from_csv("build_canada", csv, start_year: 2026)

      assert_equal 1, result[:inserted]
      assert_equal 1, result[:errors].size
      assert TiktokStat.exists?(account: "build_canada", date: Date.new(2026, 4, 5))
    end

    test "upsert_from_csv rolls year over when months wrap" do
      csv = "\"Date\",\"Video Views\",\"Profile Views\",\"Likes\",\"Comments\",\"Shares\"\n" \
        "\"December 31\",\"100\",\"1\",\"1\",\"0\",\"0\"\n" \
        "\"January 1\",\"200\",\"2\",\"2\",\"0\",\"0\"\n"

      result = TiktokStat.upsert_from_csv("build_canada", csv, start_year: 2025)

      assert_equal 2, result[:inserted]
      assert TiktokStat.exists?(account: "build_canada", date: Date.new(2025, 12, 31))
      assert TiktokStat.exists?(account: "build_canada", date: Date.new(2026, 1, 1))
    end

    test "upsert_from_csv updates existing rows" do
      TiktokStat.create!(account: "build_canada", date: Date.new(2026, 4, 4), video_views: 1)

      result = TiktokStat.upsert_from_csv("build_canada", CSV_WITH_BOM, start_year: 2026)

      assert_equal 1, result[:inserted]
      assert_equal 1, result[:updated]
      assert_equal 641, TiktokStat.find_by!(account: "build_canada", date: Date.new(2026, 4, 4)).video_views
    end

    test "upsert_from_upload extracts CSV from a zip and infers year from filename" do
      require "zip"

      Tempfile.create([ "Overview_2026-04-04_build_canada", ".zip" ]) do |tempfile|
        Zip::OutputStream.open(tempfile.path) do |zip|
          zip.put_next_entry("Overview.csv")
          zip.write(CSV_WITH_BOM)
        end

        upload = ActionDispatch::Http::UploadedFile.new(
          tempfile: File.open(tempfile.path),
          filename: File.basename(tempfile.path),
          type: "application/zip"
        )

        result = TiktokStat.upsert_from_upload("build_canada", upload)

        assert_equal 2, result[:inserted]
        assert_empty result[:errors]
        assert TiktokStat.exists?(account: "build_canada", date: Date.new(2026, 4, 4))
      end
    end
  end
end
