require "test_helper"

# Revisions, snapshots, datasets and the dictionary.
class PublicApiCatalogTest < PublicApiTestCase
  test "committed revisions are listed newest first, say whether they are served, and page with a cursor" do
    api_get "/v1/revisions", limit: 2
    assert_conforms("listRevisions", status: 200)
    assert_equal %w[gid://buildcanada/Revision/32 gid://buildcanada/Revision/31], ids, "the open revision 33 is not listed"
    assert_equal [ false, true ], body["data"].map { |r| r["served"] }
    assert_equal 31, body.dig("meta", "revision")
    assert_equal "/v1/revisions?limit=2", body.dig("links", "self")

    api_get "/v1/revisions", limit: 2, cursor: next_cursor
    assert_conforms("listRevisions", status: 200)
    assert_equal %w[gid://buildcanada/Revision/30 gid://buildcanada/Revision/14], ids
    assert_nil next_cursor
  end

  test "a revision says what it read, the snapshots naming it, and its derived build" do
    api_get "/v1/revisions/31"
    assert_conforms("getRevision", status: 200)
    data = body["data"]
    assert_equal [ 31, "resolution", "2026-10-01T02:49:22Z" ], data.values_at("number", "kind", "committed_at")
    assert_equal({ GRANTS => "6" }, data.dig("inputs", "slices"))
    assert_equal [ "daily-2026-10-01" ], data["snapshots"]
    assert_equal "summary_reconciles", data.dig("derived", "checks", 0, "name")
    assert_equal "31", response.headers["BC-Revision"]
    assert_match(/\A"r31-[0-9a-f]{12}"\z/, response.headers["ETag"])
    assert_cache_control "public, max-age=31536000, immutable"

    api_get "/v1/revisions/14"
    assert_conforms("getRevision", status: 200)
    assert_equal [ "release", [ "release-14" ], nil ], body["data"].values_at("kind", "snapshots", "derived")
    assert_equal "release-14", body.dig("meta", "snapshot")

    api_get "/v1/revisions/32"
    assert_conforms("getRevision", status: 200)
    refute body.dig("data", "served"), "committed after the latest derived build"
  end

  test "the latest revision is the newest the derived tables are built at, cached briefly" do
    api_get "/v1/revisions/latest"
    assert_conforms("getLatestRevision", status: 200)
    assert_equal 31, body.dig("data", "number")
    assert_equal "/v1/revisions/31", body.dig("links", "self")
    assert_cache_control "public, max-age=30"
  end

  test "an open or unknown revision is not_found" do
    api_get "/v1/revisions/33"
    assert_problem("getRevision", 404, "not_found")
    api_get "/v1/revisions/99"
    assert_problem("getRevision", 404, "not_found")
    api_get "/v1/revisions/0"
    assert_problem("getRevision", 400, "invalid_parameter")
  end

  test "an unchanged revision answers 304 with its ETag, costing no units" do
    api_get "/v1/revisions/31"
    etag = response.headers["ETag"]
    api_get "/v1/revisions/31", headers: { "If-None-Match" => etag }
    assert_conforms("getRevision", status: 304)
    assert_empty response.body
    assert_equal etag, response.headers["ETag"]
    assert_equal "0", response.headers["BC-Usage-Units"]
    api_get "/v1/revisions/31", headers: { "If-None-Match" => %(W/"r31-000000000000", #{etag}) }
    assert_response :not_modified
    api_get "/v1/revisions/30", headers: { "If-None-Match" => etag }
    assert_response :ok
  end

  test "snapshots name revisions, and as_of takes a snapshot's name" do
    api_get "/v1/snapshots"
    assert_conforms("listSnapshots", status: 200)
    assert_equal %w[daily-2026-10-01 release-14], body["data"].map { |s| s["name"] }
    api_get "/v1/snapshots/release-14"
    assert_conforms("getSnapshot", status: 200)
    assert_equal [ 14, "goldset" ], body["data"].values_at("revision", "held_by")
    api_get "/v1/snapshots/nothing"
    assert_problem("getSnapshot", 404, "not_found")

    api_get "/v1/entities/#{DIAMOND_VALLEY}", as_of: "daily-2026-10-01"
    assert_conforms("getEntity", status: 200)
    assert_equal [ 31, "daily-2026-10-01" ], body["meta"].values_at("revision", "snapshot")
    assert_equal "/v1/entities/#{DIAMOND_VALLEY}?as_of=31", body.dig("links", "self")
    assert_includes body.dig("data", "cite"), "revision 31 (snapshot daily-2026-10-01)"
    assert_cache_control "public, max-age=31536000, immutable"
  end

  test "datasets describe the spending sources the revision reads and the registry tables" do
    api_get "/v1/datasets", limit: 200
    assert_conforms("listDatasets", status: 200)
    keys = body["data"].map { |d| d["asset_key"] }
    assert_equal keys.sort, keys
    assert_equal [ CONTRACTS, GAC, TRANSFERS, GRANTS, "entities/entities", "entities/identifiers", "entities/mention_occurrences",
                   "entities/relationships" ].sort, keys
    grants = body["data"].find { |d| d["asset_key"] == GRANTS }
    assert_equal 9, grants.dig("coverage", "rows"), "the live and archive rows of the publications revision 31 reads"
    assert_equal "2026-09-26T04:59:18Z", grants.dig("freshness", "latest_retrieved_at")
    assert_includes grants["caveats"].map { |c| c["code"] }, "agreement_value_not_paid"
    assert_equal "/v1/spending?source=proactive_grants&as_of=31", grants.dig("links", "records")
    entities = body["data"].find { |d| d["asset_key"] == "entities/entities" }
    assert_equal 9, entities.dig("coverage", "rows")
    assert_nil body["data"].find { |d| d["asset_key"] == "entities/mention_occurrences" }.dig("coverage", "rows")
  end

  test "datasets page by asset key and filter by prefix" do
    api_get "/v1/datasets", prefix: "entities/", limit: 2
    assert_conforms("listDatasets", status: 200)
    first = body["data"].map { |d| d["asset_key"] }
    assert_equal 2, first.size
    api_get "/v1/datasets", prefix: "entities/", limit: 2, cursor: next_cursor
    rest = body["data"].map { |d| d["asset_key"] }
    assert(first.all? { |k| k.start_with?("entities/") } && rest.all? { |k| k.start_with?("entities/") })
    assert_empty first & rest
  end

  test "a dataset is found by its percent-encoded or bare asset key" do
    get "/v1/datasets/sources%2Fca%2Ftbs%2Fproactive_grants"
    assert_conforms("getDataset", status: 200)
    assert_equal "/v1/datasets/sources%2Fca%2Ftbs%2Fproactive_grants?as_of=31", body.dig("links", "self")
    get "/v1/datasets/sources/ca/tbs/proactive_grants", params: { as_of: "30" }
    assert_conforms("getDataset", status: 200)
    assert_equal 30, body.dig("meta", "revision")
    assert_equal 8, body.dig("data", "coverage", "rows")
    get "/v1/datasets/sources%2Fnothing"
    assert_problem("getDataset", 404, "not_found")
  end

  test "the dictionary lists terms and each term's per-asset notes" do
    api_get "/v1/dictionary", q: "fiscal"
    assert_conforms("listDictionaryTerms", status: 200)
    assert_includes body["data"].map { |t| t["term"] }, "fiscal_year"

    api_get "/v1/dictionary/fiscal_year"
    assert_conforms("getDictionaryTerm", status: 200)
    assert_includes body.dig("data", "asset_notes").keys, GRANTS
    assert_empty body.dig("meta", "caveats")
    api_get "/v1/dictionary/record_type"
    assert_equal({ "value" => "grant", "meaning" => "A grant agreement." }, body.dig("data", "values").find { |v| v["value"] == "grant" })

    api_get "/v1/dictionary/nothing_here"
    assert_problem("getDictionaryTerm", 404, "not_found")
  end

  test "a pinned dictionary says it is not versioned by revision, and is not cached as immutable" do
    api_get "/v1/dictionary/amount", as_of: "30"
    assert_conforms("getDictionaryTerm", status: 200)
    assert_equal [ "dictionary_not_pinned" ], body.dig("meta", "caveats").map { |c| c["code"] }
    assert_cache_control "public, max-age=300, stale-while-revalidate=3600"
  end

  test "dictionary pages cover every term once" do
    seen = []
    cursor = nil
    loop do
      api_get "/v1/dictionary", limit: 40, **(cursor ? { cursor: } : {})
      assert_conforms("listDictionaryTerms", status: 200)
      seen.concat(body["data"].map { |t| t["term"] })
      cursor = next_cursor or break
    end
    assert_equal seen.uniq, seen
    assert_equal PublicApi::Catalog.dictionary.definitions.keys.grep(/\A[a-z][a-z0-9_]*\z/).sort, seen.sort
  end
end
