require "test_helper"

class PublicApiElectionsTest < PublicApiTestCase
  def enc(id) = ERB::Util.url_encode(id)

  test "elections list newest voting day first, filter, and carry their capture" do
    api_get "/v1/elections"
    assert_conforms("listElections", status: 200)
    assert_equal [ "ca/bc/elections/2026-10-24-general", ELECTION ], ids
    assert_equal [ nil, nil ], body["meta"].values_at("revision", "snapshot"), "elections are not versioned by revision"
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, body.dig("meta", "as_of"))
    assert_cache_control "public, max-age=30"
    election = body["data"].last
    assert_equal ELECTIONS_SHA, election.dig("capture", "sha256")
    assert_equal "/v1/elections/#{enc(ELECTION)}/contests", election.dig("links", "contests")

    api_get "/v1/elections", jurisdiction: "ca-on"
    assert_empty body["data"]
    api_get "/v1/elections", limit: 1
    api_get "/v1/elections", limit: 1, cursor: next_cursor
    assert_equal [ ELECTION ], ids
    api_get "/v1/elections", as_of: "31"
    assert_problem("listElections", 400, "invalid_parameter")
  end

  test "an election by its percent-encoded ID; an unknown one is 404" do
    get "/v1/elections/#{enc(ELECTION)}"
    assert_conforms("getElection", status: 200)
    assert_equal [ "Elections BC", "2024-10-19", "2024-09-28T13:00:00-07:00" ], body["data"].values_at("administrator", "voting_day", "nominations_close_at")
    get "/v1/elections/#{enc('ca/bc/elections/1900-01-01-general')}"
    assert_problem("getElection", 404, "not_found")
  end

  test "an election's contests, with office and district" do
    get "/v1/elections/#{enc(ELECTION)}/contests"
    assert_conforms("listElectionContests", status: 200)
    assert_equal [ CONTEST_ABM, CONTEST_ABS ], ids
    contest = body["data"].first
    assert_equal "Member of the Legislative Assembly", contest.dig("office", "title")
    assert_equal({ "id" => ABM, "boundary_set_id" => DISTRICTS_SET, "code" => "ABM", "name_as_shown" => "Abbotsford-Mission" }, contest["district"])
    get "/v1/elections/#{enc(ELECTION)}/contests", params: { district: ABS }
    assert_equal [ CONTEST_ABS ], ids
    get "/v1/contests/#{enc(CONTEST_ABM)}"
    assert_conforms("getContest", status: 200)
    assert_equal "/v1/contests/#{enc(CONTEST_ABM)}/results", body.dig("data", "links", "results")
  end

  test "candidacies are served as published, with only their verified contacts" do
    get "/v1/contests/#{enc(CONTEST_ABM)}/candidacies"
    assert_conforms("listContestCandidacies", status: 200)
    assert_equal [ CAND_ALEXIS, CAND_GASPER ], ids, "by ballot name"
    alexis = body["data"].first
    assert_equal [ "123 Main Street", "Mission", "V2V 1A1" ], alexis.values_at("residence_address", "residence_city", "residence_postal_code")
    assert_equal [ [ "email", "pam@example-campaign.ca" ], [ "social", "pamalexis" ] ], alexis["contacts"].map { |c| c.values_at("kind", "value") }
    assert_equal "x", alexis["contacts"].last["platform"]
    assert_nil alexis["contacts"].first["platform"]
    assert_empty body["data"].last["contacts"], "a proposed contact is unconfirmed"
    refute_match(/604-555-0100|donate/, response.body)

    get "/v1/candidacies/#{CAND_ALEXIS}"
    assert_conforms("getCandidacy", status: 200)
    assert_equal [ "elected", [ { "name" => "Sam Agent", "role" => "official_agent" } ] ], body["data"].values_at("declared_result", "agents")
    get "/v1/candidacies/01M3TP5P62RM2298Y7AC2WYJJ9"
    assert_problem("getCandidacy", 404, "not_found")
  end

  test "results come from the latest report by default, with combined units blank" do
    get "/v1/contests/#{enc(CONTEST_ABM)}/results"
    assert_conforms("listContestResults", status: 200)
    assert_equal [ 1894, 2625, 12, nil ], body["data"].map { |r| r["value"] }
    assert_equal "advance", body["data"].last["reported_under"]
    get "/v1/contests/#{enc(CONTEST_ABM)}/results", params: { measure: "rejected" }
    assert_equal [ 12 ], body["data"].map { |r| r["value"] }
    get "/v1/contests/#{enc(CONTEST_ABM)}/results", params: { report: REPORT, limit: 2 }
    assert_equal 2, body["data"].size
    get "/v1/contests/#{enc(CONTEST_ABM)}/results", params: { report: REPORT, limit: 2, cursor: next_cursor }
    assert_equal [ 12, nil ], body["data"].map { |r| r["value"] }
    get "/v1/contests/#{enc(CONTEST_ABM)}/results", params: { report: "01M3TP69B6TM9F579VB93ZHFNX" }
    assert_problem("listContestResults", 404, "not_found")
    get "/v1/contests/#{enc(CONTEST_ABS)}/results"
    assert_conforms("listContestResults", status: 200)
    assert_empty body["data"]

    get "/v1/elections/#{enc(ELECTION)}/result-reports"
    assert_conforms("listElectionResultReports", status: 200)
    assert_equal [ [ REPORT, "official", RESULTS_SHA ] ], body["data"].map { |r| [ r["id"], r["stage"], r.dig("capture", "sha256") ] }
  end

  test "districts carry their boundary as GeoJSON, in lists only when asked" do
    get "/v1/districts/#{enc(ABM)}"
    assert_conforms("getDistrict", status: 200)
    geometry = body.dig("data", "geometry")
    assert_equal "MultiPolygon", geometry["type"]
    assert_equal [ -122.3, 49.1 ], geometry.dig("coordinates", 0, 0, 0)
    assert_equal [ "ca-bc", "district", "Electoral Districts Act" ], body.dig("data", "boundary_set").values_at("jurisdiction", "kind", "legal_instrument")

    get "/v1/districts", params: { boundary_set: DISTRICTS_SET }
    assert_conforms("listDistricts", status: 200)
    assert_equal [ ABM, ABS ], ids
    assert(body["data"].all? { |d| d["geometry"].nil? })
    get "/v1/districts", params: { jurisdiction: "ca-bc", expand: "geometry" }
    assert_equal [ "MultiPolygon", nil ], body["data"].map { |d| d.dig("geometry", "type") }, "ABS has no stored boundary"
    get "/v1/districts/#{enc('ca/bc/electoral-districts/2023/zzz')}"
    assert_problem("getDistrict", 404, "not_found")
  end
end
