require "test_helper"
require "open3"

class ProcessMunicipalFinancialStatementsTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("script/process_municipal_financial_statements.rb").to_s

  test "rejects a failed extractor without failed-only mode" do
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, SCRIPT, "--province", "on", "--failed-extractor", "headline",
      chdir: Rails.root.to_s
    )

    refute status.success?
    assert_includes stderr, "--failed-extractor requires --failed-only"
  end

  test "rejects an unknown failed extractor" do
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, SCRIPT, "--province", "on", "--failed-extractor", "unknown",
      chdir: Rails.root.to_s
    )

    refute status.success?
    assert_includes stderr, "invalid argument: --failed-extractor unknown"
  end

  test "rejects parser targeting for headline failures" do
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, SCRIPT, "--province", "on", "--rerun", "failed", "--failed-only",
      "--failed-extractor", "headline", "--failed-parser", "parser-v1",
      chdir: Rails.root.to_s
    )

    refute status.success?
    assert_includes stderr, "--failed-parser only supports the detailed failed extractor"
  end
end
