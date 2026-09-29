require "test_helper"

# Each phase 1 tool, called over MCP: results match the tool's outputSchema
# and carry what the /v1 operation it wraps returns (provenance, cite,
# caveats), a summary that ends with the citations, and the units of the
# operations it ran.
class McpToolsTest < PublicApiTestCase
  setup { @key = key_with(%w[read:public usage:read]) }

  def assert_ends_with_citations(result)
    text = summary_text(result)
    citations = result.dig("structuredContent", "citations")
    assert citations.present?, "citations"
    assert text.end_with?("Cite:\n" + citations.map { |c| "- #{c}" }.join("\n")), text.last(400)
    assert_equal result["structuredContent"], JSON.parse(result["content"].last["text"]), "the JSON text block mirrors structuredContent"
  end

  test "search_entities matches names and identifiers, and says how each hit matched" do
    result = call_tool("search_entities", { query: "Diamond Valley", jurisdiction: "ca-ab" }, token: @key)
    refute result["isError"]
    hit = result.dig("structuredContent", "data", 0)
    assert_equal [ "gid://buildcanada/Entity/#{DIAMOND_VALLEY}", "exact" ], [ hit.dig("entity", "id"), hit.dig("match", "kind") ]
    assert_equal 11, result.dig("structuredContent", "meta", "release")
    assert_ends_with_citations(result)
    assert_equal "3", response.headers["BC-Usage-Units"]
    assert_equal "mcp.search_entities", response.headers["BC-Operation"]

    result = call_tool("search_entities", { query: "107511586" }, token: @key, era: :legacy)
    assert_equal [ "identifier" ], result.dig("structuredContent", "data").map { |h| h.dig("match", "kind") }.uniq

    result = call_tool("search_entities", { query: "Diamond Valey Comunity", fuzzy: true }, token: @key)
    kinds = result.dig("structuredContent", "data").map { |h| h.dig("match", "kind") }
    assert_includes kinds, "fuzzy"
    assert_match(/a candidate to check/, summary_text(result))

    # Pages: the cursor from one call fetches the next page.
    first = call_tool("search_entities", { query: "Diamond Valley", fuzzy: true, limit: 1 }, token: @key)
    cursor = first.dig("structuredContent", "meta", "next_cursor")
    assert cursor
    second = call_tool("search_entities", { query: "Diamond Valley", fuzzy: true, limit: 1, cursor: }, token: @key)
    refute_equal first.dig("structuredContent", "data"), second.dig("structuredContent", "data")
  end

  test "get_entity reads an entity with identifiers, relationships and lineage" do
    result = call_tool("get_entity", { id: DIAMOND_VALLEY, include: %w[identifiers relationships lineage] }, token: @key)
    refute result["isError"], result.inspect.first(500)
    sc = result["structuredContent"]
    entity = sc.dig("entity", "data")
    assert_equal "Town of Diamond Valley", entity["name"]
    assert_equal [ "4806014" ], entity["identifiers"].map { |i| i["value"] }
    assert entity["relationships"].any? { |r| r["predicate"] == "located_within" }
    assert_equal [ BLACK_DIAMOND, TURNER_VALLEY ].map { |id| "gid://buildcanada/Entity/#{id}" }.sort,
      sc.dig("lineage", "predecessors").map { |s| s.dig("entity", "id") }.sort
    assert_equal [], sc.dig("lineage", "successors")
    assert_equal [ entity["cite"] ], sc["citations"]
    assert_match(/Predecessors: Town of (Black Diamond|Turner Valley)/, summary_text(result))
    assert_ends_with_citations(result)
    assert_equal "3", response.headers["BC-Usage-Units"], "getEntity plus lineage both ways"
    assert_nil sc["redirected_from"]

    result = call_tool("get_entity", { id: "gid://buildcanada/Entity/#{HERITAGE}" }, token: @key)
    assert_nil result.dig("structuredContent", "lineage")
    assert_equal "1", response.headers["BC-Usage-Units"]
  end

  test "get_entity follows a merged ID to its survivor" do
    result = call_tool("get_entity", { id: DUP }, token: @key)
    refute result["isError"]
    assert_equal "gid://buildcanada/Entity/#{DUP}", result.dig("structuredContent", "redirected_from")
    assert_equal "gid://buildcanada/Entity/#{FOUNDATION}", result.dig("structuredContent", "entity", "data", "id")
    assert_match(/merged/, summary_text(result))
  end

  test "get_entity: an unknown entity is a structured not_found" do
    error = assert_tool_error(call_tool("get_entity", { id: UNKNOWN }, token: @key), "not_found")
    assert_equal 404, error["status"]
    assert_equal "1", response.headers["BC-Usage-Units"], "an error costs 1 unit, as on REST"
  end

  test "entity_spending returns the summary under the fixed rules, its caveats and the largest rows" do
    result = call_tool("entity_spending", { id: DIAMOND_VALLEY }, token: @key, era: :legacy)
    refute result["isError"]
    sc = result["structuredContent"]
    rows = sc.dig("summary", "data").map { |r| r.values_at("source", "fiscal_year", "amount", "measure") }
    assert_equal [ %w[proactive_grants 2024-25 150000.00 agreement_value], %w[proactive_grants 2025-26 0.00 agreement_value],
                   %w[transfer_payments 2024-25 880000.00 payments_or_expenditure] ], rows
    codes = sc.dig("summary", "meta", "caveats").map { |c| c["code"] }
    assert_includes codes, "not_cross_source_total"
    assert_includes codes, "agreement_value_not_paid"
    # Latest revisions only, so the archive copy of G1 is left out (#140, c8fef70).
    assert_equal 4, sc.dig("top_records", "data").size
    assert_equal "880000.00", sc.dig("top_records", "data", 0, "amount")
    assert_equal "Build Canada data release 11, https://data.buildcanada.com/v1/entities/#{DIAMOND_VALLEY}/spending/summary?role=recipient&as_of=11", sc["citations"].first
    assert_equal sc.dig("top_records", "data").map { |r| r["cite"] }, sc["citations"].drop(1)
    text = summary_text(result)
    assert_match(/Never add amounts across sources/, text)
    assert_match(/Unlinked rows naming this entity, not counted: 1/, text)
    assert_match(/an aggregate row/, text)
    assert_ends_with_citations(result)
    assert_equal "4", response.headers["BC-Usage-Units"], "summary (3) plus one page of rows (1)"

    # A department's payments, by counterparty; top 0 skips the rows.
    result = call_tool("entity_spending", { id: HERITAGE, role: "payer", group_by: %w[source counterparty], top: 0, as_of: "11" }, token: @key)
    sc = result["structuredContent"]
    assert_nil sc["top_records"]
    assert sc.dig("summary", "data").any? { |r| r.dig("counterparty", "id") == "gid://buildcanada/Entity/#{DIAMOND_VALLEY}" }
    assert_equal "3", response.headers["BC-Usage-Units"]

    # Pinned to an earlier release.
    result = call_tool("entity_spending", { id: DIAMOND_VALLEY, group_by: [ "source" ], source: [ "proactive_grants" ], as_of: "10" }, token: @key)
    assert_equal [ [ "proactive_grants", "125000.00" ] ], result.dig("structuredContent", "summary", "data").map { |r| r.values_at("source", "amount") }
    assert_equal 10, result.dig("structuredContent", "top_records", "meta", "release")
  end

  test "search_spending finds rows by text, party and filters, with cites and caveats" do
    result = call_tool("search_spending", { query: "cultural spaces", latest_revision_only: true, sort: "-amount" }, token: @key)
    refute result["isError"], result.inspect.first(500)
    sc = result["structuredContent"]
    assert_equal [ "gid://buildcanada/SpendingRecord/#{G1_A1}" ], sc["data"].select { |r| r["acquisition"] == "live" }.map { |r| r["id"] }
    assert_equal sc["data"].map { |r| r["cite"] }, sc["citations"]
    assert_includes sc.dig("meta", "caveats").map { |c| c["code"] }, "not_cross_source_total"
    assert_ends_with_citations(result)

    result = call_tool("search_spending", { recipient: FOUNDATION, amount_min: 30000 }, token: @key)
    assert_equal [ "gid://buildcanada/SpendingRecord/#{G2}" ], result.dig("structuredContent", "data").map { |r| r["id"] }

    first = call_tool("search_spending", { payer: HERITAGE, limit: 2 }, token: @key)
    cursor = first.dig("structuredContent", "meta", "next_cursor")
    second = call_tool("search_spending", { payer: HERITAGE, limit: 2, cursor: }, token: @key)
    assert_empty first.dig("structuredContent", "data").map { |r| r["id"] } & second.dig("structuredContent", "data").map { |r| r["id"] }
    assert_equal "1", response.headers["BC-Usage-Units"]
  end

  test "describe_data explains spending semantics, sources, datasets, terms and caveats" do
    result = call_tool("describe_data", { topic: "spending semantics" }, token: @key)
    sc = result["structuredContent"]
    assert_equal "spending_semantics", sc["kind"]
    assert_match(/must never be\s+added/, sc["guidance"])
    assert_includes sc["sources"].map { |s| s["source"] }, "proactive_grants"
    assert_includes sc["caveats"].map { |c| c["code"] }, "not_cross_source_total"
    assert_ends_with_citations(result)

    sc = call_tool("describe_data", { topic: "proactive_grants" }, token: @key)["structuredContent"]
    assert_equal [ "source", [ "agreement_value" ], [ GRANTS ] ], [ sc["kind"], sc["sources"].map { |s| s["measure"] }, sc["datasets"].map { |d| d["asset_key"] } ]
    assert_equal "2", response.headers["BC-Usage-Units"]

    assert_equal "dataset", call_tool("describe_data", { topic: GRANTS }, token: @key).dig("structuredContent", "kind")
    sc = call_tool("describe_data", { topic: "fiscal_year" }, token: @key)["structuredContent"]
    assert_equal [ "term", [ "fiscal_year" ] ], [ sc["kind"], sc["terms"].map { |t| t["term"] } ]
    sc = call_tool("describe_data", { topic: "agreement_value_not_paid" }, token: @key)["structuredContent"]
    assert_equal [ "caveat", "https://data.buildcanada.com/api/caveats#agreement_value_not_paid" ], [ sc["kind"], sc.dig("caveats", 0, "docs") ]
    assert_equal "1", response.headers["BC-Usage-Units"], "a lookup without a /v1 call still costs 1 unit"
    assert_equal "caveats", call_tool("describe_data", { topic: "caveats" }, token: @key).dig("structuredContent", "kind")
    assert_equal "datasets", call_tool("describe_data", { topic: "datasets" }, token: @key).dig("structuredContent", "kind")
    assert_equal "search", call_tool("describe_data", { topic: "revision" }, token: @key).dig("structuredContent", "kind")
  end
end
