require "test_helper"

class PublicApiEntitiesTest < PublicApiTestCase
  test "an entity, with provenance, cite and pinned links" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}"
    assert_conforms("getEntity", status: 200)
    data = body["data"]
    assert_equal "gid://buildcanada/Entity/#{DIAMOND_VALLEY}", data["id"]
    assert_equal [ "Diamond Valley" ], data["aliases"]
    assert_equal "/v1/entities/#{DIAMOND_VALLEY}/lineage?as_of=11", data.dig("links", "lineage")
    assert_equal({ "origin" => "roster", "source_key" => "ca-ab/municipal_affairs/municipalities", "capture_sha256" => ROSTER_SHA,
                   "row_number" => 212 }, data.dig("provenance", "source"))
    assert_equal({ "row" => 212 }, data.dig("provenance", "locator"))
    assert_equal 11, data.dig("provenance", "release")
    assert_equal "Build Canada entity registry release 11, gid://buildcanada/Entity/#{DIAMOND_VALLEY}; " \
      "from roster ca-ab/municipal_affairs/municipalities, row 212.", data["cite"]
    assert_equal "/v1/entities/#{DIAMOND_VALLEY}?as_of=11", body.dig("links", "self")
    assert_cache_control "public, max-age=300, stale-while-revalidate=3600"
  end

  test "address keys never leave the API, at any depth" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}"
    assert_equal({ "municipality_type_raw" => "Town", "office" => {} }, body.dig("data", "attributes"))
    api_get "/v1/entities/#{DIAMOND_VALLEY}/relationships", predicate: "located_within", direction: "out"
    assert_conforms("listEntityRelationships", status: 200)
    dguid = body["data"].find { |r| r["object_ref"] }
    assert_equal({ "dguid" => "2021A00054806014", "vintage" => "2021" }, dguid["attributes"])
  end

  test "as_of pins the release, by number, date or timestamp" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}", as_of: "10"
    assert_conforms("getEntity", status: 200)
    assert_equal [], body.dig("data", "aliases")
    assert_equal 10, body.dig("data", "provenance", "release")
    assert_equal "10", body.dig("meta", "as_of")
    assert_equal "/v1/entities/#{DIAMOND_VALLEY}?as_of=10", body.dig("links", "self")
    assert_cache_control "public, max-age=31536000, immutable"

    api_get "/v1/entities/#{DIAMOND_VALLEY}", as_of: "2026-09-25"
    assert_equal 10, body.dig("meta", "release")
    api_get "/v1/entities/#{DIAMOND_VALLEY}", as_of: "2026-09-27T06:14:02Z"
    assert_equal 11, body.dig("meta", "release")

    api_get "/v1/entities/#{NEW}", as_of: "10"
    assert_problem("getEntity", 404, "not_found")
    api_get "/v1/entities/#{NEW}"
    assert_conforms("getEntity", status: 200)
  end

  test "an as_of in the future resolves to the latest but is not cached as immutable" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}", as_of: "2099-01-01T00:00:00Z"
    assert_conforms("getEntity", status: 200)
    assert_equal 11, body.dig("meta", "release")
    assert_cache_control "public, max-age=300, stale-while-revalidate=3600"
  end

  test "as_of before the first release is not_yet_published, and a bad one is invalid" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}", as_of: "2020-01-01"
    problem = assert_problem("getEntity", 404, "not_yet_published")
    assert_equal 10, problem["earliest_release"]
    api_get "/v1/entities/#{DIAMOND_VALLEY}", as_of: "9"
    assert_problem("getEntity", 404, "not_yet_published")
    api_get "/v1/entities/#{DIAMOND_VALLEY}", as_of: "2026-02-30"
    assert_equal "as_of", assert_problem("getEntity", 400, "invalid_parameter").dig("errors", 0, "parameter")
    api_get "/v1/entities/#{DIAMOND_VALLEY}", as_of: "latest"
    assert_problem("getEntity", 400, "invalid_parameter")
  end

  test "the path takes the bare ULID or the percent-encoded gid; anything else is a 400" do
    get "/v1/entities/gid%3A%2F%2Fbuildcanada%2FEntity%2F#{DIAMOND_VALLEY}"
    assert_conforms("getEntity", status: 200)
    assert_equal "gid://buildcanada/Entity/#{DIAMOND_VALLEY}", body.dig("data", "id")
    api_get "/v1/entities/not-an-id"
    assert_problem("getEntity", 400, "invalid_parameter")
    api_get "/v1/entities/#{UNKNOWN}"
    assert_problem("getEntity", 404, "not_found")
  end

  test "a merged entity is 301 to its survivor, pinned, for the entity and its collections" do
    api_get "/v1/entities/#{DUP}", expand: "identifiers"
    problem = assert_problem("getEntity", 301, "redirected")
    location = "/v1/entities/#{FOUNDATION}?expand=identifiers&as_of=11"
    assert_equal location, response.headers["Location"]
    assert_equal location, problem["location"]
    api_get "/v1/entities/#{DUP}/spending/summary"
    assert_problem("getEntitySpendingSummary", 301, "redirected")
    assert_equal "/v1/entities/#{FOUNDATION}/spending/summary?as_of=11", response.headers["Location"]
  end

  test "expand embeds identifiers and the first outgoing relationships" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}", expand: "identifiers,relationships"
    assert_conforms("getEntity", status: 200)
    assert_equal [ "ca.statcan.csd_uid" ], body.dig("data", "identifiers").map { |i| i["namespace"] }
    assert body.dig("data", "identifiers", 0, "verified")
    assert(body.dig("data", "relationships").all? { |r| r["direction"] == "out" && r["subject_id"].end_with?(DIAMOND_VALLEY) })
    api_get "/v1/entities/#{DIAMOND_VALLEY}"
    refute body["data"].key?("identifiers")
    api_get "/v1/entities/#{DIAMOND_VALLEY}", expand: "lineage"
    assert_problem("getEntity", 400, "invalid_parameter")
  end

  test "fields returns only the fields asked for, plus id and cite" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}", fields: "name,status"
    assert_conforms("getEntity", status: 200, projected: true)
    assert_equal %w[id name status cite], body["data"].keys
    api_get "/v1/entities", fields: "name", limit: 2
    assert_conforms("listEntities", status: 200, projected: true)
    assert(body["data"].all? { |e| e.keys == %w[id name cite] })
    api_get "/v1/entities", fields: "name,street"
    assert_equal "fields", assert_problem("listEntities", 400, "invalid_parameter").dig("errors", 0, "parameter")
  end

  test "entities list by filter, page by cursor and never list persons" do
    all = page_through("/v1/entities", limit: 3)
    assert_equal all.sort, all
    refute_includes all, "gid://buildcanada/Entity/#{PERSON}"
    assert_includes all, "gid://buildcanada/Entity/#{NEW}"
    assert_equal all, page_through("/v1/entities", limit: 200)

    api_get "/v1/entities", class: "government_org", subtype: "municipal_government", status: "active"
    assert_conforms("listEntities", status: 200)
    assert_equal [ "gid://buildcanada/Entity/#{DIAMOND_VALLEY}" ], ids
    assert_equal "/v1/entities?class=government_org&subtype=municipal_government&status=active&as_of=11", body.dig("links", "self")
  end

  test "entities sort by name, and count=exact counts at 2 more units" do
    names = page_through("/v1/entities", key: "name", sort: "name", limit: 2)
    assert_equal names.sort, names
    api_get "/v1/entities", count: "exact", jurisdiction: "ca-ab"
    assert_conforms("listEntities", status: 200)
    assert_equal body["data"].size, body.dig("meta", "count")
    assert_equal "3", response.headers["BC-Usage-Units"]
    assert_cache_control "private, no-store"
    api_get "/v1/entities", limit: 51
    assert_equal "2", response.headers["BC-Usage-Units"]
  end

  test "valid_on reads partial dates at their widest" do
    api_get "/v1/entities", valid_on: "2022-06-01", class: "government_org"
    assert_includes ids, "gid://buildcanada/Entity/#{TURNER_VALLEY}"
    refute_includes ids, "gid://buildcanada/Entity/#{DIAMOND_VALLEY}"
    api_get "/v1/entities", valid_on: "2023-01-01", class: "government_org"
    refute_includes ids, "gid://buildcanada/Entity/#{TURNER_VALLEY}"
    assert_includes ids, "gid://buildcanada/Entity/#{DIAMOND_VALLEY}"
    api_get "/v1/entities", valid_on: "1977-06-01", subtype: "municipal_government"
    assert_equal [ BLACK_DIAMOND, TURNER_VALLEY ].map { |id| "gid://buildcanada/Entity/#{id}" }.sort, ids.sort
  end

  test "a cursor stays on its release and must come back with the same parameters" do
    api_get "/v1/entities", limit: 2, as_of: "10"
    cursor = next_cursor
    api_get "/v1/entities", limit: 2, cursor: cursor
    assert_conforms("listEntities", status: 200)
    assert_equal 10, body.dig("meta", "release"), "the cursor's release answers when as_of is left out"
    assert_includes body.dig("links", "self"), "as_of=10"
    assert_cache_control "public, max-age=31536000, immutable"

    api_get "/v1/entities", limit: 2, cursor: cursor, as_of: "11"
    problem = assert_problem("listEntities", 409, "release_mismatch")
    assert_equal 10, problem["cursor_release"]
    api_get "/v1/entities", limit: 2, cursor: cursor, class: "organization"
    assert_equal "cursor", assert_problem("listEntities", 400, "invalid_parameter").dig("errors", 0, "parameter")
    api_get "/v1/entities", cursor: "#{cursor}x"
    assert_problem("listEntities", 400, "invalid_parameter")
  end

  test "unknown and repeated parameters are refused, all at once" do
    api_get "/v1/entities", colour: "blue", class: "planet"
    problem = assert_problem("listEntities", 400, "invalid_parameter")
    assert_equal %w[class colour], problem["errors"].map { |e| e["parameter"] }.sort
    get "/v1/entities?class=organization&class=jurisdiction"
    assert_response :ok, "Rack keeps the last of repeated scalar parameters"
    get "/v1/entities?class[]=organization"
    assert_problem("listEntities", 400, "invalid_parameter")
  end

  test "identifiers page, and filter by namespace" do
    api_get "/v1/entities/#{FOUNDATION}/identifiers", limit: 1
    assert_conforms("listEntityIdentifiers", status: 200)
    first = body["data"].map { |i| i["value"] }
    api_get "/v1/entities/#{FOUNDATION}/identifiers", limit: 1, cursor: next_cursor
    assert_conforms("listEntityIdentifiers", status: 200)
    assert_equal %w[107511586RR0001 107511586], first + body["data"].map { |i| i["value"] }, "namespace order: bn15 before bn9"
    api_get "/v1/entities/#{FOUNDATION}/identifiers", namespace: "ca.cra.bn15"
    assert_equal [ "107511586RR0001" ], body["data"].map { |i| i["value"] }
  end

  test "relationships in and out, with the object entity, and never person predicates" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/relationships"
    assert_conforms("listEntityRelationships", status: 200)
    directions = body["data"].map { |r| [ r["predicate"], r["direction"] ] }.tally
    assert_equal({ [ "succeeded_by", "in" ] => 2, [ "located_within", "out" ] => 2, [ "located_within", "in" ] => 1 }, directions)
    alberta = body["data"].find { |r| r["object_id"]&.end_with?(ALBERTA) }
    assert_equal "Alberta", alberta.dig("object", "name")
    assert_match(/relationship located_within of gid/, alberta["cite"])

    api_get "/v1/entities/#{DIAMOND_VALLEY}/relationships", direction: "in", predicate: "succeeded_by"
    assert_equal 2, body["data"].size
    api_get "/v1/entities/#{DIAMOND_VALLEY}/relationships", valid_on: "2015-01-01", direction: "in"
    assert_equal [ "located_within" ], body["data"].map { |r| r["predicate"] }

    api_get "/v1/entities/#{FOUNDATION}/relationships", key: persons_key
    refute_includes body["data"].map { |r| r["predicate"] }, "director_of"
    api_get "/v1/entities/#{FOUNDATION}/relationships", predicate: "director_of"
    assert_problem("listEntityRelationships", 400, "invalid_parameter")
  end

  test "lineage walks predecessors and successors, nearest first" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/lineage"
    assert_conforms("getEntityLineage", status: 200)
    assert_equal [ BLACK_DIAMOND, TURNER_VALLEY ].sort, body["data"].map { |s| s.dig("entity", "id").split("/").last }.sort
    step = body["data"].first
    assert_equal [ 1, "amalgamated", "2023-01-01", "in" ], [ step["depth"], step["event"], step["effective_date"], step.dig("relationship", "direction") ]

    api_get "/v1/entities/#{BLACK_DIAMOND}/lineage", direction: "successors"
    assert_conforms("getEntityLineage", status: 200)
    assert_equal [ "gid://buildcanada/Entity/#{DIAMOND_VALLEY}" ], body["data"].map { |s| s.dig("entity", "id") }

    api_get "/v1/entities/#{DIAMOND_VALLEY}/lineage", limit: 1
    first = body["data"].map { |s| s.dig("entity", "id") }
    api_get "/v1/entities/#{DIAMOND_VALLEY}/lineage", limit: 1, cursor: next_cursor
    refute_equal first, body["data"].map { |s| s.dig("entity", "id") }
    api_get "/v1/entities/#{DIAMOND_VALLEY}/lineage", max_depth: 11
    assert_problem("getEntityLineage", 400, "invalid_parameter")
  end

  test "person entities need read:persons: 401 anonymous, 403 without the scope" do
    api_get "/v1/entities/#{PERSON}"
    problem = assert_problem("getEntity", 401, "unauthenticated")
    assert_equal "read:persons", problem["required_scope"]

    api_get "/v1/entities/#{PERSON}", key: key_with(%w[read:public])
    problem = assert_problem("getEntity", 403, "insufficient_scope")
    assert_equal "read:persons", problem["required_scope"]
    assert_equal %(Bearer error="insufficient_scope", scope="read:persons"), response.headers["WWW-Authenticate"]

    api_get "/v1/entities/#{PERSON}", key: persons_key
    assert_conforms("getEntity", status: 200)
    assert_equal "person", body.dig("data", "entity_class")
    assert_cache_control "private, no-store"
  end

  test "persons are never listed, even with read:persons" do
    api_get "/v1/entities", class: "person"
    assert_problem("listEntities", 401, "unauthenticated")
    api_get "/v1/entities", class: "person", key: persons_key
    assert_problem("listEntities", 422, "query_too_broad")
    api_get "/v1/entities", key: persons_key, limit: 200
    refute_includes ids, "gid://buildcanada/Entity/#{PERSON}"
  end

  private

  def page_through(path, key: "id", **params)
    seen = []
    cursor = nil
    loop do
      api_get path, **params, **(cursor ? { cursor: } : {})
      assert_conforms("listEntities", status: 200)
      seen.concat(body["data"].map { |d| d[key] })
      cursor = next_cursor or break
    end
    seen
  end
end
