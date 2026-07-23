require "test_helper"

class Warehouse::Source::Fetcher::TorontoCandidateListTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:status, :body)

  class FakeHttp
    attr_reader :requested_urls

    def initialize(responses_by_file)
      @responses_by_file = responses_by_file
      @requested_urls = []
    end

    def get(url)
      @requested_urls << url
      file = File.basename(url)
      @responses_by_file.fetch(file) { FakeResponse.new(404, "") }
    end
  end

  BASE_URL = "https://www.toronto.ca/data/elections/candidate_list".freeze

  def feed(payload_key, payload, seq: "1784656380447")
    JSON.generate("seq" => seq, "spaces" => "    ", payload_key => payload)
  end

  test "combines the four feeds into one canonical body without volatile keys" do
    http = FakeHttp.new(
      "mayorCandidates_2026.json" => FakeResponse.new(200, feed("candidates", [ { "name" => "Chow, Olivia" } ])),
      "councilorCandidates_2026.json" => FakeResponse.new(200, feed("ward", [ { "num" => "1", "candidate" => [] } ])),
      "trusteeCandidates_2026.json" => FakeResponse.new(200, feed("schoolBoard", [ { "id" => 3, "ward" => [] } ])),
      "withdrawnCandidates_2026.json" => FakeResponse.new(200, feed("candidates", []))
    )

    body = Warehouse::Source::Fetcher::TorontoCandidateList.new(BASE_URL, year: "2026", http: http).call
    parsed = JSON.parse(body)

    assert_equal %w[year mayor councillor trustee withdrawn], parsed.keys
    assert_equal "2026", parsed["year"]
    assert_equal [ { "name" => "Chow, Olivia" } ], parsed["mayor"]
    assert_equal [ { "num" => "1", "candidate" => [] } ], parsed["councillor"]
    refute_includes body, "seq"
  end

  test "identical data with different seq stamps produces an identical body" do
    build = ->(seq) do
      http = FakeHttp.new(
        "mayorCandidates_2026.json" => FakeResponse.new(200, feed("candidates", [ { "name" => "Chow, Olivia" } ], seq: seq)),
        "councilorCandidates_2026.json" => FakeResponse.new(200, feed("ward", [], seq: seq))
      )
      Warehouse::Source::Fetcher::TorontoCandidateList.new(BASE_URL, year: "2026", http: http).call
    end

    assert_equal build.call("111"), build.call("222")
  end

  test "missing trustee and withdrawn feeds read as empty" do
    http = FakeHttp.new(
      "mayorCandidates_2026.json" => FakeResponse.new(200, feed("candidates", [])),
      "councilorCandidates_2026.json" => FakeResponse.new(200, feed("ward", []))
    )

    parsed = JSON.parse(Warehouse::Source::Fetcher::TorontoCandidateList.new(BASE_URL, year: "2026", http: http).call)

    assert_equal [], parsed["trustee"]
    assert_equal [], parsed["withdrawn"]
  end

  test "a missing mayor feed raises" do
    http = FakeHttp.new(
      "councilorCandidates_2026.json" => FakeResponse.new(200, feed("ward", []))
    )

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::TorontoCandidateList.new(BASE_URL, year: "2026", http: http).call
    end
    assert_match(/HTTP 404/, error.message)
  end

  test "an unexpected feed shape raises" do
    http = FakeHttp.new(
      "mayorCandidates_2026.json" => FakeResponse.new(200, JSON.generate("seq" => "1", "unexpected" => []))
    )

    error = assert_raises(RuntimeError) do
      Warehouse::Source::Fetcher::TorontoCandidateList.new(BASE_URL, year: "2026", http: http).call
    end
    assert_match(/missing "candidates" array/, error.message)
  end

  test "requires a year" do
    assert_raises(ArgumentError) do
      Warehouse::Source::Fetcher::TorontoCandidateList.new(BASE_URL, year: nil)
    end
  end

  test "tolerates a UTF-8 BOM in the response body" do
    http = FakeHttp.new(
      "mayorCandidates_2026.json" => FakeResponse.new(200, "﻿" + feed("candidates", [])),
      "councilorCandidates_2026.json" => FakeResponse.new(200, feed("ward", []))
    )

    parsed = JSON.parse(Warehouse::Source::Fetcher::TorontoCandidateList.new(BASE_URL, year: "2026", http: http).call)
    assert_equal [], parsed["mayor"]
  end
end
