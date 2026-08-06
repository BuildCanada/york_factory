require "test_helper"

class Warehouse::Source::Fetcher::DownloadStrategiesTest < ActiveSupport::TestCase
  class RecordingLoader
    attr_reader :calls

    def initialize
      @calls = []
    end

    def load(**arguments)
      @calls << arguments
    end
  end

  test "yearly spending strategies own filenames and withdrawal scopes" do
    cases = [
      [
        Warehouse::Source::Fetcher::NsercAwards.new("https://example.test/catalogue"),
        Warehouse::Source::Fetcher::NsercAwards::YearDownload.new(
          year: 2024, url: "https://example.test/2024.csv", io: StringIO.new("nserc"), checksum: checksum("nserc")
        ),
        "nserc-awards-2024-#{checksum("nserc").first(12)}.csv",
        2024
      ],
      [
        Warehouse::Source::Fetcher::SshrcAwards.new("https://example.test/catalogue"),
        Warehouse::Source::Fetcher::SshrcAwards::YearDownload.new(
          year: 2023, url: "https://example.test/2023.csv", io: StringIO.new("sshrc"), checksum: checksum("sshrc")
        ),
        "sshrc-awards-2023-#{checksum("sshrc").first(12)}.csv",
        2023
      ],
      [
        Warehouse::Source::Fetcher::TransferPayments.new("https://example.test/catalogue"),
        Warehouse::Source::Fetcher::TransferPayments::YearDownload.new(
          year: 2025, fiscal_year: 2024, url: "https://example.test/2025.csv",
          io: StringIO.new("transfer"), checksum: checksum("transfer")
        ),
        "transfer-payments-2025-#{checksum("transfer").first(12)}.csv",
        2024
      ]
    ]

    cases.each do |strategy, result, filename, fiscal_year|
      strategy.define_singleton_method(:each_year) { |&block| block.call(result) }
      download = strategy.each_download.to_a.sole
      loader = RecordingLoader.new
      ingestion = Object.new
      ingestion.define_singleton_method(:spending_loader) { loader }

      download.load(ingestion)

      assert_equal filename, download.filename
      assert_equal({ fiscal_year: }, loader.calls.sole.dig(:withdrawal_scope))
    end
  end

  test "single spending strategies own archive filenames and loaders" do
    cases = [
      [ Warehouse::Source::Fetcher::CihrAwards.new("https://example.test/cihr"),
        Warehouse::Source::Fetcher::CihrAwards::Download.new(
          io: StringIO.new("cihr"), checksum: checksum("cihr")
        ), "cihr-awards-#{checksum("cihr").first(12)}.ndjson" ],
      [ Warehouse::Source::Fetcher::GlobalAffairsProjects.new("https://example.test/global"),
        Warehouse::Source::Fetcher::GlobalAffairsProjects::Download.new(
          io: StringIO.new("global"), checksum: checksum("global")
        ), "global-affairs-projects-#{checksum("global").first(12)}.csv" ]
    ]

    cases.each do |strategy, result, filename|
      strategy.define_singleton_method(:call) { result }
      download = strategy.each_download.to_a.sole
      loader = RecordingLoader.new
      ingestion = Object.new
      ingestion.define_singleton_method(:spending_loader) { loader }

      download.load(ingestion)

      assert_equal filename, download.filename
      assert_equal({ body: result.io }, loader.calls.sole)
    end
  end

  test "normalized API and election strategies own their loaders" do
    cases = [
      [ Warehouse::Source::Fetcher::WorldBankDownload.new("https://example.test/world-bank"),
        :world_bank_econ_loader, :json_content ],
      [ Warehouse::Source::Fetcher::StatcanVectors.new("https://example.test/statcan?vectors=1"),
        :statcan_econ_loader, :json_content ],
      [ Warehouse::Source::Fetcher::TorontoCandidateList.new("https://example.test/toronto", year: 2026),
        :toronto_candidates_loader, :json_content ],
      [ Warehouse::Source::Fetcher::BramptonCandidateList.new("https://example.test/brampton", year: 2026),
        :brampton_candidates_loader, :json_content ],
      [ Warehouse::Source::Fetcher::HamiltonCandidateList.new("https://example.test/hamilton", year: 2026),
        :hamilton_candidates_loader, :json_content ]
    ]

    cases.each do |strategy, loader_method, argument|
      strategy.define_singleton_method(:call) { "canonical" }
      download = strategy.each_download.to_a.sole
      loader = RecordingLoader.new
      ingestion = Object.new
      ingestion.define_singleton_method(loader_method) { loader }

      download.load(ingestion)

      assert_equal({ argument => "canonical" }, loader.calls.sole)
    end
  end

  private

  def checksum(body)
    Digest::SHA256.hexdigest(body)
  end
end
