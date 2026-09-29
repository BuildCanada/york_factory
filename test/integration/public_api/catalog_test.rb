require "test_helper"

# Releases, datasets, the dictionary and exports.
class PublicApiCatalogTest < PublicApiTestCase
  test "releases are listed newest first and page with a cursor" do
    api_get "/v1/releases", limit: 1
    assert_conforms("listReleases", status: 200)
    assert_equal [ "gid://buildcanada/Release/11" ], ids
    assert_equal [], body["data"].first["inputs"], "list pages leave inputs empty"
    assert_equal "/v1/releases?limit=1", body.dig("links", "self")

    api_get "/v1/releases", limit: 1, cursor: next_cursor
    assert_conforms("listReleases", status: 200)
    assert_equal [ "gid://buildcanada/Release/10" ], ids
    assert_nil next_cursor
  end

  test "a release pins its inputs, counts and checks" do
    api_get "/v1/releases/11"
    assert_conforms("getRelease", status: 200)
    data = body["data"]
    assert_equal 11, data["number"]
    assert_equal "2026-09-27T06:14:02Z", data["published_at"]
    snapshot = data["inputs"].find { |i| i["kind"] == "iceberg_snapshot" && i["asset"] == GRANTS }
    assert_equal "2534519102996296639", snapshot["snapshot_id"]
    assert_equal ROSTER_SHA, data["inputs"].find { |i| i["kind"] == "capture" }["sha256"]
    assert_equal 9, data["counts"]["entities"], "10 entity versions, one closed by release 11"
    assert_includes data["checks"].map { |c| c["name"] }, "api_columns_allowlisted"
    assert_equal "11", response.headers["BC-Release"]
    assert_match(/\A"r11-[0-9a-f]{12}"\z/, response.headers["ETag"])
    assert_cache_control "public, max-age=31536000, immutable"
  end

  test "the latest release is release 11, cached briefly" do
    api_get "/v1/releases/latest"
    assert_conforms("getLatestRelease", status: 200)
    assert_equal 11, body.dig("data", "number")
    assert_equal "/v1/releases/11", body.dig("links", "self")
    assert_cache_control "public, max-age=30"
  end

  test "a release before the earliest is not_yet_published; a missing one not_found" do
    api_get "/v1/releases/3"
    assert_equal 10, assert_problem("getRelease", 404, "not_yet_published")["earliest_release"]
    api_get "/v1/releases/12"
    assert_problem("getRelease", 404, "not_found")
    api_get "/v1/releases/0"
    assert_problem("getRelease", 400, "invalid_parameter")
  end

  test "an unchanged release answers 304 with its ETag, costing no units" do
    api_get "/v1/releases/11"
    etag = response.headers["ETag"]
    api_get "/v1/releases/11", headers: { "If-None-Match" => etag }
    assert_conforms("getRelease", status: 304)
    assert_empty response.body
    assert_equal etag, response.headers["ETag"]
    assert_equal "0", response.headers["BC-Usage-Units"]
    api_get "/v1/releases/11", headers: { "If-None-Match" => %(W/"r11-000000000000", #{etag}) }
    assert_response :not_modified
    api_get "/v1/releases/10", headers: { "If-None-Match" => etag }
    assert_response :ok
  end

  test "datasets describe every spending source and registry table, with release facts" do
    api_get "/v1/datasets", limit: 200
    assert_conforms("listDatasets", status: 200)
    keys = body["data"].map { |d| d["asset_key"] }
    assert_equal keys.sort, keys
    assert_includes keys, GRANTS
    assert_includes keys, "entities/entities"
    grants = body["data"].find { |d| d["asset_key"] == GRANTS }
    assert_equal 8, grants.dig("coverage", "rows"), "live and archive rows of the pinned snapshots"
    assert_equal "2023-24", grants.dig("coverage", "from_fiscal_year")
    assert_equal "2025-26", grants.dig("coverage", "to_fiscal_year")
    assert_includes grants["caveats"].map { |c| c["code"] }, "agreement_value_not_paid"
    assert_equal "/v1/spending?source=proactive_grants&as_of=11", grants.dig("links", "records")
    entities = body["data"].find { |d| d["asset_key"] == "entities/entities" }
    assert_equal "https://files.buildcanada.com/releases/11/entities.parquet", entities.dig("bulk", 0, "url")
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
    assert_equal "/v1/datasets/sources%2Fca%2Ftbs%2Fproactive_grants?as_of=11", body.dig("links", "self")
    get "/v1/datasets/sources/ca/tbs/proactive_grants", params: { as_of: "10" }
    assert_conforms("getDataset", status: 200)
    assert_equal 10, body.dig("meta", "release")
    assert_equal 7, body.dig("data", "coverage", "rows")
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
    api_get "/v1/dictionary/record_type"
    assert_equal({ "value" => "grant", "meaning" => "A grant agreement." }, body.dig("data", "values").find { |v| v["value"] == "grant" })

    api_get "/v1/dictionary/nothing_here"
    assert_problem("getDictionaryTerm", 404, "not_found")
  end

  test "a pinned dictionary says it is not versioned by release, and is not cached as immutable" do
    api_get "/v1/dictionary/amount", as_of: "10"
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
    assert_equal PublicApi::Catalog.definitions.keys.grep(/\A[a-z][a-z0-9_]*\z/).sort, seen.sort
  end

  test "exports list a release's Parquet files, not its manifest" do
    api_get "/v1/exports"
    assert_conforms("listExports", status: 200)
    assert_equal %w[entities.entities entities.identifiers], body["data"].map { |e| e["table"] }
    assert_equal "11", response.headers["BC-Release"]
    api_get "/v1/exports", release: 10
    assert_conforms("listExports", status: 200)
    assert_empty body["data"]
    api_get "/v1/exports", table: "entities.identifiers"
    assert_equal [ "entities.identifiers" ], body["data"].map { |e| e["table"] }
    api_get "/v1/exports", release: 99
    assert_problem("listExports", 404, "not_found")
  end
end
