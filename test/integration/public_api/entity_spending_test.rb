require "test_helper"

class PublicApiEntitySpendingTest < PublicApiTestCase
  DV_ROWS = [ G1_A0, G1_A1, G_AGGREGATE, G_BLANK, G_ARCHIVE, T1 ].freeze

  test "an entity's rows are its linked occurrences in the role" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending"
    assert_conforms("listEntitySpending", status: 200)
    assert_equal DV_ROWS, keys
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending", as_of: "10"
    assert_equal DV_ROWS - [ G1_A1 ], keys
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending", latest_revision_only: "true", source: "proactive_grants"
    assert_equal [ G1_A1, G_AGGREGATE, G_BLANK ], keys, "not the archive copy of an older revision"
    api_get "/v1/entities/#{HERITAGE}/spending", role: "payer", count: "exact"
    assert_conforms("listEntitySpending", status: 200)
    assert_equal 12, body.dig("meta", "count")
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending", role: "payer"
    assert_empty body["data"]
  end

  test "include_proposed adds proposed rows and shows their parties' link_status" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending", include_proposed: "true"
    assert_conforms("listEntitySpending", status: 200)
    assert_equal (DV_ROWS + [ G_PROPOSED ]).sort, keys
    proposed = body["data"].find { |r| r["id"].end_with?(G_PROPOSED) }
    assert_equal "proposed", proposed["parties"].find { |p| p["field"] == "recipient" }["link_status"]
    assert_includes body.dig("meta", "caveats").map { |c| c["code"] }, "proposed_included"
  end

  test "the summary follows the fixed rules: per source, latest revisions, no aggregates, blanks counted" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/summary"
    assert_conforms("getEntitySpendingSummary", status: 200)
    rows = body["data"].map { |r| r.values_at("source", "fiscal_year", "records", "agreements", "amount", "amount_missing", "currency", "measure") }
    assert_equal [
      [ "proactive_grants", "2024-25", 1, 1, "150000.00", 0, "CAD", "agreement_value" ],
      [ "proactive_grants", "2025-26", 1, 1, "0.00", 1, "CAD", "agreement_value" ],
      [ "transfer_payments", "2024-25", 1, 1, "880000.00", 0, "CAD", "payments_or_expenditure" ]
    ], rows
    meta = body["meta"]
    assert_equal [ "recipient", [ "source", "fiscal_year" ], 1, 1 ], meta.values_at("role", "group_by", "aggregated_rows_excluded", "unlinked_occurrences")
    codes = meta["caveats"].map { |c| c["code"] }
    assert_equal %w[not_cross_source_total latest_revision_only linked_only aggregates_excluded amount_missing agreement_value_not_paid measure_ambiguous], codes
    unlinked = "/v1/entities/#{DIAMOND_VALLEY}/spending/unlinked?role=recipient&as_of=11"
    assert_equal "Only linked occurrences are counted. 1 unlinked occurrences with this name: #{unlinked}.", meta["caveats"][2]["text"]
    assert_equal({ "self" => "/v1/entities/#{DIAMOND_VALLEY}/spending/summary?as_of=11", "unlinked" => unlinked,
                   "records" => "/v1/entities/#{DIAMOND_VALLEY}/spending?role=recipient&as_of=11" }, body["links"])
    assert_equal "3", response.headers["BC-Usage-Units"]
  end

  test "the summary as of release 10 counts that release's latest revision" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/summary", as_of: "10", group_by: "source"
    assert_conforms("getEntitySpendingSummary", status: 200)
    grants = body["data"].find { |r| r["source"] == "proactive_grants" }
    assert_equal [ nil, 2, "125000.00", 1 ], grants.values_at("fiscal_year", "records", "amount", "amount_missing")
    assert_equal %w[source], body.dig("meta", "group_by")
  end

  test "source is always a grouping key, and filters narrow the summary" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/summary", group_by: "fiscal_year", source: "transfer_payments", fiscal_year: "2024-25"
    assert_conforms("getEntitySpendingSummary", status: 200)
    assert_equal [ %w[transfer_payments 2024-25] ], body["data"].map { |r| r.values_at("source", "fiscal_year") }
    assert_equal %w[source fiscal_year], body.dig("meta", "group_by")
  end

  test "group_by=counterparty, from the read model's counterparty summary, agrees with its summary" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/summary", group_by: "source"
    precomputed = body["data"].to_h { |r| [ r["source"], r.values_at("records", "amount", "amount_missing") ] }
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/summary", group_by: "counterparty"
    assert_conforms("getEntitySpendingSummary", status: 200)
    assert(body["data"].all? { |r| r.dig("counterparty", "id") == "gid://buildcanada/Entity/#{HERITAGE}" })
    split = body["data"].to_h { |r| [ r["source"], r.values_at("records", "amount", "amount_missing") ] }
    assert_equal precomputed, split
    assert_equal 1, body.dig("meta", "aggregated_rows_excluded")

    api_get "/v1/entities/#{HERITAGE}/spending/summary", role: "payer", group_by: "counterparty,fiscal_year", source: "proactive_grants"
    assert_conforms("getEntitySpendingSummary", status: 200)
    rows = body["data"].map { |r| [ r.dig("counterparty", "id")&.split("/")&.last, r["fiscal_year"], r["records"], r["amount"] ] }
    assert_includes rows, [ DIAMOND_VALLEY, "2024-25", 1, "150000.00" ], "the latest amendment only, and not the aggregate"
    assert_includes rows, [ nil, "2024-25", 2, "35000.00" ], "rows with no linked recipient: a person's and a proposed one"
  end

  test "unlinked occurrences with the entity's name, for a reader to check" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/unlinked"
    assert_conforms("listEntityUnlinkedSpending", status: 200)
    assert_equal 1, body["data"].size
    item = body["data"].first
    assert_equal [ "unlinked", "period_spans_change" ], item["party"].values_at("link_status", "reason")
    assert_equal [ "gid://buildcanada/Entity/#{DIAMOND_VALLEY}", "gid://buildcanada/Entity/#{BLACK_DIAMOND}" ], item.dig("party", "candidates")
    assert_equal({ "id" => "gid://buildcanada/SpendingRecord/#{T2}", "source" => "transfer_payments", "fiscal_year" => "2023-24",
                   "amount" => "12000.00", "currency" => "CAD", "payer" => "Canadian Heritage", "title" => nil }, item["record"])
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/unlinked", reason: "conflict"
    assert_empty body["data"]
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/unlinked", reason: "excluded_individual"
    assert_problem("listEntityUnlinkedSpending", 400, "invalid_parameter")
  end

  test "a summary of an unknown entity is 404; a person's spending is read:public" do
    api_get "/v1/entities/#{UNKNOWN}/spending/summary"
    assert_problem("getEntitySpendingSummary", 404, "not_found")
    api_get "/v1/entities/#{PERSON}/spending"
    assert_conforms("listEntitySpending", status: 200)
  end

  private

  def keys = ids.map { |id| id.split("/").last }
end
