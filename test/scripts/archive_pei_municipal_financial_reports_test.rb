# frozen_string_literal: true

require "test_helper"
require Rails.root.join("script/archive_pei_municipal_financial_reports")

class ArchivePeiMunicipalFinancialReportsTest < ActiveSupport::TestCase
  setup do
    @download_dir = Pathname(Dir.mktmpdir("pei-downloads"))
    @archiver = ArchivePeiMunicipalFinancialReports.new(
      manifest_path: "/tmp/not-read.json",
      index_glob: "/tmp/not-read-*.json",
      output_path: "/tmp/not-written.json",
      retrieved_at: "2026-08-24T00:00:00Z",
      download_dir: @download_dir
    )
  end

  teardown { FileUtils.remove_entry(@download_dir) }

  test "finds a Chrome download by its official file name" do
    file = @download_dir.join("2024 Abram Village Audited Financial Statements.pdf")
    file.write("%PDF-test")
    url = "https://wdf.princeedwardisland.ca/download/dms?" \
      "objectId=fa84cee9-20c7-42dc-8419-e98e6135d79d&" \
      "fileName=2024%20Abram%20Village%20Audited%20Financial%20Statements.pdf"

    assert_equal file, @archiver.send(:local_path_for, url)
  end

  test "finds Chrome's numbered duplicate download" do
    file = @download_dir.join("2024 Abram Village Audited Financial Statements (1).pdf")
    file.write("%PDF-test")
    url = "https://wdf.princeedwardisland.ca/download/dms?" \
      "objectId=691a1913-e7c7-4be5-adb5-7a0eced2328e&" \
      "fileName=2024%20Abram%20Village%20Audited%20Financial%20Statements.pdf"

    assert_equal file, @archiver.send(:local_path_for, url)
  end

  test "maps Wayback captures to official PEI object IDs" do
    object_id = "fa84cee9-20c7-42dc-8419-e98e6135d79d"
    url = "https://wdf.princeedwardisland.ca/download/dms?objectId=#{object_id}&" \
      "fileName=2024%20Abram%20Village%20Audited%20Financial%20Statements.pdf"
    response = [
      %w[timestamp original statuscode mimetype digest],
      [ "20250102030405", url, "200", "application/pdf", "WAYBACK-DIGEST" ]
    ]
    scraper = @archiver.instance_variable_get(:@scraper)
    scraper.stub(:fetch_wayback_index, JSON.generate(response)) do
      captures = @archiver.send(:wayback_candidates, [ { "url" => url } ])

      assert_equal 1, captures.fetch(object_id).length
      assert_equal "20250102030405", captures.fetch(object_id).sole.fetch("wayback_timestamp")
      assert_equal url, captures.fetch(object_id).sole.fetch("original_url")
    end
  end
end
