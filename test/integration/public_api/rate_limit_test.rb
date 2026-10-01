require "test_helper"

class PublicApiRateLimitTest < PublicApiTestCase
  # One request per operation, and the units x-bc-units gives it.
  REQUESTS = {
    "getIndex" => "/v1", "getOpenapi" => "/v1/openapi.json", "getMe" => "/v1/me", "listRevisions" => "/v1/revisions",
    "getLatestRevision" => "/v1/revisions/latest", "getRevision" => "/v1/revisions/31", "listSnapshots" => "/v1/snapshots",
    "getSnapshot" => "/v1/snapshots/release-14", "listDatasets" => "/v1/datasets",
    "getDataset" => "/v1/datasets/entities%2Fentities", "listDictionaryTerms" => "/v1/dictionary",
    "getDictionaryTerm" => "/v1/dictionary/amount", "searchEntities" => "/v1/search?q=diamond",
    "listEntities" => "/v1/entities", "getEntity" => "/v1/entities/#{FactFactoryFixtures::DIAMOND_VALLEY}",
    "listEntityIdentifiers" => "/v1/entities/#{FactFactoryFixtures::DIAMOND_VALLEY}/identifiers",
    "listEntityRelationships" => "/v1/entities/#{FactFactoryFixtures::DIAMOND_VALLEY}/relationships",
    "getEntityLineage" => "/v1/entities/#{FactFactoryFixtures::DIAMOND_VALLEY}/lineage",
    "listEntitySpending" => "/v1/entities/#{FactFactoryFixtures::DIAMOND_VALLEY}/spending",
    "getEntitySpendingSummary" => "/v1/entities/#{FactFactoryFixtures::DIAMOND_VALLEY}/spending/summary",
    "listEntityUnlinkedSpending" => "/v1/entities/#{FactFactoryFixtures::DIAMOND_VALLEY}/spending/unlinked",
    "resolveIdentifier" => "/v1/identifiers/ca.cra.bn9/107511586", "listSpending" => "/v1/spending",
    "listSpendingSources" => "/v1/spending/sources", "getSpendingRecord" => "/v1/spending/#{FactFactoryFixtures::G2}",
    "getUsage" => "/v1/me/usage",
    "listElections" => "/v1/elections", "getElection" => "/v1/elections/ca%2Fbc%2Felections%2F2024-10-19-general",
    "listElectionContests" => "/v1/elections/ca%2Fbc%2Felections%2F2024-10-19-general/contests",
    "listElectionResultReports" => "/v1/elections/ca%2Fbc%2Felections%2F2024-10-19-general/result-reports",
    "getContest" => "/v1/contests/ca%2Fbc%2Felections%2F2024-10-19-general%2Fmla%2Fabm",
    "listContestCandidacies" => "/v1/contests/ca%2Fbc%2Felections%2F2024-10-19-general%2Fmla%2Fabm/candidacies",
    "listContestResults" => "/v1/contests/ca%2Fbc%2Felections%2F2024-10-19-general%2Fmla%2Fabm/results",
    "getCandidacy" => "/v1/candidacies/#{FactFactoryFixtures::CAND_ALEXIS}", "listDistricts" => "/v1/districts",
    "getDistrict" => "/v1/districts/ca%2Fbc%2Felectoral-districts%2F2023%2Fabm"
  }.freeze

  test "every operation answers per the contract and reports its x-bc-units" do
    key = key_with(%w[read:public usage:read])
    assert_equal PublicApi::Spec.operations.keys.sort, REQUESTS.keys.sort
    REQUESTS.each do |operation_id, path|
      get path, headers: { "Authorization" => "Bearer #{key}" }
      assert_conforms(operation_id, status: 200)
      op = PublicApi::Spec.operation(operation_id)
      assert_equal op.units_base.to_s, response.headers["BC-Usage-Units"], operation_id
      assert_equal operation_id, response.headers["BC-Operation"]
    end
  end

  test "every 200 carries RateLimit, RateLimit-Policy and BC-Quota-Remaining" do
    api_get "/v1/entities", key: key_with(%w[read:public])
    assert_conforms("listEntities", status: 200)
    assert_equal %("minute";q=120;w=60, "month";q=100000;w=2592000), response.headers["RateLimit-Policy"]
    assert_match(/\A"minute";r=119;t=\d+\z/, response.headers["RateLimit"])
    assert_equal "99999", response.headers["BC-Quota-Remaining"]

    api_get "/v1/entities"
    assert_equal %("minute";q=30;w=60, "day";q=1000;w=86400), response.headers["RateLimit-Policy"]
    assert_equal "999", response.headers["BC-Quota-Remaining"]
  end

  test "an anonymous caller past 30 units a minute gets 429 rate_limited, and no units are taken" do
    travel_to Time.utc(2026, 9, 29, 12, 0, 5) do
      15.times { api_get "/v1/entities", limit: 51 }
      assert_match(/\A"minute";r=0;t=55\z/, response.headers["RateLimit"])
      api_get "/v1/entities"
      problem = assert_problem("listEntities", 429, "rate_limited")
      assert_equal "55", response.headers["Retry-After"]
      assert_equal [ 55, "anonymous", "https://data.buildcanada.com/api/concepts/bulk-access.md" ], problem.values_at("retry_after_seconds", "plan", "bulk_url")
      assert_equal "0", response.headers["BC-Usage-Units"]
      assert_equal "970", response.headers["BC-Quota-Remaining"], "the refused request took nothing"
    end
    travel_to Time.utc(2026, 9, 29, 12, 1, 0) do
      api_get "/v1/entities"
      assert_conforms("listEntities", status: 200)
    end
  end

  test "the daily allowance of an anonymous caller is quota_exceeded until the next UTC day" do
    travel_to Time.utc(2026, 9, 29, 23, 0, 0) do
      store = PublicApi::RateLimiter.store
      store.write("public_api:rl:ip:127.0.0.1:day:20260929", 1000, raw: true)
      api_get "/v1/entities"
      problem = assert_problem("listEntities", 429, "quota_exceeded")
      assert_equal 3600, problem["retry_after_seconds"]
      assert_equal "0", response.headers["BC-Quota-Remaining"]
    end
  end

  test "a key's rate is its own, and the monthly quota is its account's" do
    user = users(:member)
    first = issue_key(user:, scopes: %w[read:public]).raw_key
    second = issue_key(user:, scopes: %w[read:public]).raw_key
    travel_to Time.utc(2026, 9, 29, 12, 0, 0) do
      api_get "/v1/entities", key: first, limit: 200
      api_get "/v1/entities", key: second
      assert_match(/"minute";r=119;/, response.headers["RateLimit"])
      assert_equal "99997", response.headers["BC-Quota-Remaining"]
    end
  end

  test "a 304 costs no units but counts one toward the rate" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}"
    etag = response.headers["ETag"]
    api_get "/v1/entities/#{DIAMOND_VALLEY}", headers: { "If-None-Match" => etag }
    assert_conforms("getEntity", status: 304)
    assert_equal "0", response.headers["BC-Usage-Units"]
    assert_match(/"minute";r=28;/, response.headers["RateLimit"])
    assert_equal "999", response.headers["BC-Quota-Remaining"]
  end

  test "errors cost 1 unit, whatever the operation would have" do
    api_get "/v1/entities/#{UNKNOWN}/spending/summary"
    assert_problem("getEntitySpendingSummary", 404, "not_found")
    assert_equal "1", response.headers["BC-Usage-Units"]
    assert_equal "999", response.headers["BC-Quota-Remaining"]
  end

  test "a request the edge Worker signed is not limited here" do
    path = "/v1/entities?limit=2"
    signed = Edge::Signature.headers(method: "GET", path:, secret: "edge-test-secret")
    Edge.stub(:secret, "edge-test-secret") do
      get path, headers: signed
    end
    assert_conforms("listEntities", status: 200, limited: false)
    refute response.headers.key?("RateLimit"), "the Worker sends the RateLimit headers"
    assert_equal "1", response.headers["BC-Usage-Units"], "the Worker settles units from this header"

    with_env("PUBLIC_API_REQUIRE_EDGE" => "true") do
      Edge.stub(:secret, "edge-test-secret") do
        get path
        assert_problem("listEntities", 401, "unauthenticated")
        get path, headers: signed.merge("BC-Edge-Signature" => "v1=#{'0' * 64}")
        assert_problem("listEntities", 401, "unauthenticated")
      end
    end
  end

  test "the limiter can be switched off" do
    PublicApi::RateLimiter.store = nil
    api_get "/v1/entities"
    assert_conforms("listEntities", status: 200, limited: false)
    refute response.headers.key?("RateLimit")
    assert_equal "1", response.headers["BC-Usage-Units"]
  end
end
