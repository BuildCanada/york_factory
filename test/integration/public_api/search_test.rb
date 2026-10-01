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
    api_get "/v1/search", q: "Diamond Valley", as_of: "30"
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

  test "mode=fuzzy degrades to exact while no fuzzy backend exists, and says so" do
    api_get "/v1/search", q: "Diamond Valley Comunity Foundation", mode: "fuzzy"
    assert_conforms("searchEntities", status: 200)
    assert_empty body["data"], "a misspelling finds nothing without fuzzy matching"
    assert_equal [ "fuzzy_unavailable" ], body.dig("meta", "caveats").map { |c| c["code"] }
    api_get "/v1/search", q: "Diamond Valley Community Foundation", mode: "fuzzy"
    assert_equal [ { "kind" => "exact", "score" => 1, "matched_on" => "name" } ], body["data"].map { |h| h["match"] }
    api_get "/v1/search", q: "Diamond Valley Community Foundation"
    assert_empty body.dig("meta", "caveats"), "mode=exact has nothing to degrade"
  end

  test "a fuzzy backend plugs in through FactFactory::FuzzyNames" do
    backend = Class.new do
      def available? = true

      # Every name that shares a word with the query, scored by overlap: a stand-in for tin.
      def arm(current:)
        <<~SQL
          SELECT n.entity_id, 'fuzzy', 0.5::double precision, CASE n.kind WHEN 'alias' THEN 'alias:' || n.name ELSE n.kind END, 3
          FROM #{FactFactoryRecord.table('entity_names')} n
          WHERE n.normalized_name LIKE '%' || split_part(CAST(:normalized AS text), ' ', 4) || '%' AND #{current}
        SQL
      end
    end.new
    FactFactory::FuzzyNames.adapter = backend
    api_get "/v1/search", q: "Diamond Valley Comunity Foundation", mode: "fuzzy"
    assert_conforms("searchEntities", status: 200)
    assert_equal [ [ FOUNDATION, "fuzzy" ] ], body["data"].map { |h| [ h.dig("entity", "id").split("/").last, h.dig("match", "kind") ] }
    assert_empty body.dig("meta", "caveats")
  end

  test "search pages by cursor and filters by class and jurisdiction" do
    api_get "/v1/search", q: "107511586", limit: 1
    seen = ids_of_hits
    while next_cursor
      api_get "/v1/search", q: "107511586", limit: 1, cursor: next_cursor
      assert_conforms("searchEntities", status: 200)
      seen.concat(ids_of_hits)
    end
    assert_equal seen.uniq, seen
    assert_equal 2, seen.size
    api_get "/v1/search", q: "diamond valley", class: "government_org", jurisdiction: "ca-ab"
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

  test "persons are searched like any entity, anonymously, by name or identifier" do
    api_get "/v1/search", q: "Jane Q. Example"
    assert_conforms("searchEntities", status: 200)
    assert_equal [ "gid://buildcanada/Entity/#{PERSON}" ], ids_of_hits
    api_get "/v1/search", q: "999999999"
    assert_equal [ "gid://buildcanada/Entity/#{PERSON}" ], ids_of_hits
    api_get "/v1/search", q: "Jane Q. Example", class: "person"
    assert_conforms("searchEntities", status: 200)
    assert_equal [ "gid://buildcanada/Entity/#{PERSON}" ], ids_of_hits
  end

  test "an identifier resolves to every entity holding it" do
    api_get "/v1/identifiers/ca.cra.bn9/107511586"
    assert_conforms("resolveIdentifier", status: 200)
    assert_equal [ FOUNDATION, NEW ].sort, body.dig("data", "matches").map { |m| m.dig("entity", "id").split("/").last }.sort
    assert_equal "2", response.headers["BC-Usage-Units"]
    api_get "/v1/identifiers/ca.cra.bn9/107511586", as_of: "30"
    assert_equal [ "gid://buildcanada/Entity/#{FOUNDATION}" ], body.dig("data", "matches").map { |m| m.dig("entity", "id") }
    api_get "/v1/identifiers/ca.cra.bn9/107511586RR0001"
    assert_equal "107511586", body.dig("data", "value"), "a program account is cut to its BN9"
    api_get "/v1/identifiers/ca.cra.bn9/000000000"
    assert_problem("resolveIdentifier", 404, "not_found")
    api_get "/v1/identifiers/ca.cra.bn9/999999999"
    assert_conforms("resolveIdentifier", status: 200)
    assert_equal [ "gid://buildcanada/Entity/#{PERSON}" ], body.dig("data", "matches").map { |m| m.dig("entity", "id") }, "a person's identifier resolves too"
  end

  private

  def ids_of_hits = body["data"].map { |h| h.dig("entity", "id") }
end
