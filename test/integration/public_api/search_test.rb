require "test_helper"

class PublicApiSearchTest < PublicApiTestCase
  test "a name matches exactly after normalization, and says so" do
    api_get "/v1/search", q: "  THE Town of Diamond-Valley "
    assert_conforms("searchEntities", status: 200)
    hit = body["data"].first
    assert_equal "gid://buildcanada/Entity/#{DIAMOND_VALLEY}", hit.dig("entity", "id")
    assert_equal({ "kind" => "exact", "score" => 1, "matched_on" => "name" }, hit["match"])
    assert_equal 20, body.dig("meta", "limit")
    assert_equal "3", response.headers["BC-Usage-Units"]
  end

  test "aliases and French names match too" do
    api_get "/v1/search", q: "Diamond Valley"
    assert_equal "alias:Diamond Valley", body["data"].find { |h| h.dig("entity", "id").end_with?(DIAMOND_VALLEY) }.dig("match", "matched_on")
    api_get "/v1/search", q: "Patrimoine canadien"
    assert_equal "name_fr", body.dig("data", 0, "match", "matched_on")
    api_get "/v1/search", q: "Diamond Valley", as_of: "10"
    refute(body["data"].any? { |h| h.dig("entity", "id").end_with?(DIAMOND_VALLEY) }, "the alias is new in release 11")
  end

  test "an identifier comes first, and a BN15 finds its BN9" do
    api_get "/v1/search", q: "107511586"
    assert_conforms("searchEntities", status: 200)
    assert_equal [ FOUNDATION, NEW ].sort, body["data"].map { |h| h.dig("entity", "id").split("/").last }.sort
    assert(body["data"].all? { |h| h["match"] == { "kind" => "identifier", "score" => 1, "matched_on" => "identifier:ca.cra.bn9" } })
    api_get "/v1/search", q: "107511586 RR 0001"
    assert_includes body["data"].map { |h| h.dig("entity", "id") }, "gid://buildcanada/Entity/#{FOUNDATION}"
  end

  test "fuzzy adds trigram candidates after exact hits, and only with mode=fuzzy" do
    api_get "/v1/search", q: "Diamond Valley Comunity Foundation"
    assert_empty body["data"]
    api_get "/v1/search", q: "Diamond Valley Comunity Foundation", mode: "fuzzy"
    assert_conforms("searchEntities", status: 200)
    fuzzy = body["data"].find { |h| h.dig("entity", "id").end_with?(FOUNDATION) }
    assert_equal "fuzzy", fuzzy.dig("match", "kind")
    assert_operator fuzzy.dig("match", "score"), :<, 1
    scores = body["data"].map { |h| h.dig("match", "score") }
    assert_equal scores.sort.reverse, scores
  end

  test "search pages by cursor and filters by class and jurisdiction" do
    api_get "/v1/search", q: "diamond valley", mode: "fuzzy", limit: 1
    seen = ids_of_hits
    while next_cursor
      api_get "/v1/search", q: "diamond valley", mode: "fuzzy", limit: 1, cursor: next_cursor
      assert_conforms("searchEntities", status: 200)
      seen.concat(ids_of_hits)
    end
    assert_equal seen.uniq, seen
    assert_operator seen.size, :>=, 3
    api_get "/v1/search", q: "diamond valley", mode: "fuzzy", class: "government_org", jurisdiction: "ca-ab"
    assert(body["data"].all? { |h| h.dig("entity", "entity_class") == "government_org" })
    api_get "/v1/search", q: "diamond", limit: 51
    assert_problem("searchEntities", 400, "invalid_parameter")
  end

  test "a query under 2 letters or digits is too broad" do
    api_get "/v1/search", q: "a."
    assert_problem("searchEntities", 422, "query_too_broad")
    api_get "/v1/search"
    assert_equal "q", assert_problem("searchEntities", 400, "invalid_parameter").dig("errors", 0, "parameter")
  end

  test "persons appear only with read:persons, only by name" do
    api_get "/v1/search", q: "Jane Q. Example"
    assert_empty body["data"]
    api_get "/v1/search", q: "999999999", key: persons_key
    assert_empty body["data"], "never by identifier"
    api_get "/v1/search", q: "Jane Q. Example", key: persons_key
    assert_conforms("searchEntities", status: 200)
    assert_equal [ "gid://buildcanada/Entity/#{PERSON}" ], ids_of_hits
    assert_cache_control "private, no-store"
    api_get "/v1/search", q: "Jane", class: "person"
    assert_problem("searchEntities", 401, "unauthenticated")
  end

  test "an identifier resolves to every entity holding it" do
    api_get "/v1/identifiers/ca.cra.bn9/107511586"
    assert_conforms("resolveIdentifier", status: 200)
    assert_equal [ FOUNDATION, NEW ].sort, body.dig("data", "matches").map { |m| m.dig("entity", "id").split("/").last }.sort
    assert_equal "2", response.headers["BC-Usage-Units"]
    api_get "/v1/identifiers/ca.cra.bn9/107511586", as_of: "10"
    assert_equal [ "gid://buildcanada/Entity/#{FOUNDATION}" ], body.dig("data", "matches").map { |m| m.dig("entity", "id") }
    api_get "/v1/identifiers/ca.cra.bn9/107511586RR0001"
    assert_equal "107511586", body.dig("data", "value"), "a program account is cut to its BN9"
    api_get "/v1/identifiers/ca.cra.bn9/000000000"
    assert_problem("resolveIdentifier", 404, "not_found")
    api_get "/v1/identifiers/ca.cra.bn9/999999999"
    assert_problem("resolveIdentifier", 404, "not_found")
  end

  private

  def ids_of_hits = body["data"].map { |h| h.dig("entity", "id") }
end
