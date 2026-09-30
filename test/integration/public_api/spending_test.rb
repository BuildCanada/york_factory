require "test_helper"

class PublicApiSpendingTest < PublicApiTestCase
  ALL_11 = [ C1, GAC1, G1_A0, G1_A1, G2, G_PERSON, G_AGGREGATE, G_BLANK, G_ARCHIVE, G_PROPOSED, G_ARCHIVE_ONLY, T1, T2 ].freeze

  test "spending rows list by spending key, with the caveats that apply" do
    assert_equal ALL_11.sort, ALL_11
    assert_equal ALL_11, page_through("/v1/spending", limit: 5)
    api_get "/v1/spending"
    codes = body.dig("meta", "caveats").map { |c| c["code"] }
    assert_equal %w[not_cross_source_total revisions_listed archive_overlaps_live], codes.first(3)
    assert_includes codes, "agreement_value_not_paid"
    refute body["data"].first.key?("parties"), "parties only with expand=parties"
    assert_equal ALL_11 - [ G1_A1 ], page_through("/v1/spending", as_of: "10")
  end

  test "sorting by amount or date puts blanks last in both directions, and pages stably" do
    by_amount = [ T1, G1_A1, G1_A0, G_ARCHIVE, G2, G_PROPOSED, C1, T2, G_PERSON, G_AGGREGATE, GAC1, G_BLANK, G_ARCHIVE_ONLY ]
    assert_equal by_amount, page_through("/v1/spending", sort: "-amount", limit: 3)
    ascending = [ G_AGGREGATE, G_PERSON, T2, C1, G_PROPOSED, G2, G1_A0, G_ARCHIVE, G1_A1, T1, GAC1, G_BLANK, G_ARCHIVE_ONLY ]
    assert_equal ascending, page_through("/v1/spending", sort: "amount", limit: 4), "ties by spending key"
    by_date = [ G2, GAC1, G1_A0, G_ARCHIVE, G1_A1 ]
    assert_equal by_date + (ALL_11 - by_date), page_through("/v1/spending", sort: "date", limit: 2)
    assert_equal by_date.reverse.values_at(0, 2, 1, 3, 4) + (ALL_11 - by_date), page_through("/v1/spending", sort: "-date", limit: 2)
  end

  test "filters: source, record type, fiscal year, amounts and text" do
    assert_equal [ C1, T1, T2 ], page_through("/v1/spending", source: "transfer_payments,proactive_contracts")
    assert_equal [ G1_A0, G1_A1, G_ARCHIVE ], page_through("/v1/spending", record_type: "contribution")
    assert_equal [ G2, T2 ], page_through("/v1/spending", fiscal_year: "2023-24")
    assert_equal [ G1_A0, G1_A1, G_ARCHIVE, T1 ], page_through("/v1/spending", amount_min: "100000.00")
    assert_equal [ G_PERSON, G_AGGREGATE ], page_through("/v1/spending", amount_max: "5000.00")
    assert_equal [ G1_A0, G1_A1, G_ARCHIVE ], page_through("/v1/spending", q: "cultural spaces")
    assert_equal [ G2, C1 ].sort, page_through("/v1/spending", q: "diamond valley community foundation")
    assert_equal ALL_11 - [ G1_A0, G_ARCHIVE ], page_through("/v1/spending", latest_revision_only: "true"),
      "the archive copy of an older revision is not the latest; an agreement only the archive has is"
    assert_equal ALL_11 - [ G1_A1, G_ARCHIVE ], page_through("/v1/spending", latest_revision_only: "true", as_of: "10"),
      "in release 10, the archive's copy of the live latest revision is left out too"
    assert_equal ALL_11 - [ G_AGGREGATE ], page_through("/v1/spending", include_aggregated: "false")
  end

  test "payer and recipient take entity IDs and match linked occurrences only" do
    assert_equal ALL_11 - [ GAC1 ], page_through("/v1/spending", payer: HERITAGE)
    assert_equal [ G1_A0, G1_A1, G_AGGREGATE, G_BLANK, G_ARCHIVE, T1 ], page_through("/v1/spending", recipient: "gid://buildcanada/Entity/#{DIAMOND_VALLEY}")
    assert_equal [ C1, G2 ], page_through("/v1/spending", recipient: FOUNDATION), "a contract's vendor is its recipient"
    api_get "/v1/spending", recipient: "Town of Diamond Valley"
    assert_equal "recipient", assert_problem("listSpending", 400, "invalid_parameter").dig("errors", 0, "parameter")
  end

  test "invalid values are named, with how to write them" do
    api_get "/v1/spending", fiscal_year: "2024-26", amount_min: "12.5", sort: "size"
    problem = assert_problem("listSpending", 400, "invalid_parameter")
    errors = problem["errors"].to_h { |e| [ e["parameter"], e["detail"] ] }
    assert_equal "Use YYYY-YY, e.g. 2024-25", errors["fiscal_year"]
    assert_match(/decimal string/, errors["amount_min"])
    assert_match(/one of/, errors["sort"])
    assert_equal "1", response.headers["BC-Usage-Units"]
    assert response.headers["RateLimit"].present?
  end

  test "count=exact counts at 2 more units, and pages over 50 cost 2" do
    api_get "/v1/spending", count: "exact"
    assert_conforms("listSpending", status: 200)
    assert_equal 13, body.dig("meta", "count")
    assert_equal "3", response.headers["BC-Usage-Units"]
    api_get "/v1/spending", count: "exact", limit: 200
    assert_equal "4", response.headers["BC-Usage-Units"]
  end

  test "a spending row: typed columns, parties, revision, provenance and cite" do
    api_get "/v1/spending/#{G1_A0}"
    assert_conforms("getSpendingRecord", status: 200)
    data = body["data"]
    assert_equal "125000.00", data["amount"]
    assert_equal "2024-25", data["fiscal_year"]
    assert_equal "agreement_value", data["measure"]
    refute data["is_latest_revision"], "amendment 1 outranks it in release 11"
    assert_equal({ "payer" => "linked", "recipient" => "linked" }, data["parties"].to_h { |p| [ p["field"], p["link_status"] ] })
    assert_equal "gid://buildcanada/Entity/#{DIAMOND_VALLEY}", data["parties"].find { |p| p["field"] == "recipient" }["entity_id"]
    capture = { "sha256" => GRANTS_SHA, "url" => "https://files.buildcanada.com/sha256/0d/#{GRANTS_SHA}",
                "source_url" => "https://open.canada.ca/data/dataset/432527ab/resource/1d15a62f", "retrieved_at" => "2026-09-19T04:12:09Z" }
    assert_equal({ "asset" => GRANTS, "release" => 11, "snapshot_id" => SNAPSHOTS[11][GRANTS], "recorded_at" => nil, "capture" => capture,
                   "locator" => nil, "source" => nil, "parser_version" => "spending-iceberg-v5", "license" => "OGL-Canada-2.0" }, data["provenance"])
    assert_equal "Treasury Board of Canada Secretariat, Proactive Disclosure of Grants and Contributions, source file sha256 0d9b2894. " \
      "Build Canada data release 11, gid://buildcanada/SpendingRecord/#{G1_A0}.", data["cite"]
    assert_equal "/v1/spending/#{G1_A0}?as_of=11", body.dig("links", "self")

    api_get "/v1/spending/#{G1_A0}", as_of: "10"
    assert body.dig("data", "is_latest_revision")
    assert_equal SNAPSHOTS[10][GRANTS], body.dig("data", "provenance", "snapshot_id")
    api_get "/v1/spending/#{G1_A1}", as_of: "10"
    assert_problem("getSpendingRecord", 404, "not_found")
    get "/v1/spending/gid%3A%2F%2Fbuildcanada%2FSpendingRecord%2F#{G1_A1}"
    assert_conforms("getSpendingRecord", status: 200)
  end

  test "is_latest_revision is the table's, not the slice's: live data outranks the archive" do
    { G_ARCHIVE => false, G_ARCHIVE_ONLY => true, G1_A1 => true, T1 => true }.each do |key, latest|
      api_get "/v1/spending/#{key}"
      assert_conforms("getSpendingRecord", status: 200)
      assert_equal latest, body.dig("data", "is_latest_revision"), key
    end
    api_get "/v1/spending", latest_revision_only: "true", source: "proactive_grants", limit: 50
    assert(body["data"].all? { |r| r["is_latest_revision"] })
  end

  test "a capture with no recorded retrieval time is not served as one" do
    api_get "/v1/spending/#{C1}"
    assert_conforms("getSpendingRecord", status: 200)
    assert_nil body.dig("data", "provenance", "capture")
  end

  test "a proposed link is never linked, and says what was proposed" do
    api_get "/v1/spending/#{G_PROPOSED}"
    party = body.dig("data", "parties").find { |p| p["field"] == "recipient" }
    assert_equal({ "link_status" => "proposed", "entity_id" => nil, "method" => "exact_name", "reason" => "proposed",
                   "candidates" => [ "gid://buildcanada/Entity/#{DIAMOND_VALLEY}" ] }, party.slice("link_status", "entity_id", "method", "reason", "candidates"))
  end

  test "mixed-currency projects: a blank amount and currency, commitments by currency" do
    api_get "/v1/spending/#{GAC1}"
    assert_conforms("getSpendingRecord", status: 200)
    data = body["data"]
    assert_nil data["amount"]
    assert_nil data["currency"]
    assert_equal({ "CAD" => "100.00", "USD" => "50.50" }, data["commitments"])
    assert_equal [ "Org A", "Org B" ], data["recipients"]
    assert_includes body.dig("meta", "caveats").map { |c| c["code"] }, "commitment_not_spending"
  end

  test "expand=raw says raw is not served yet; fields project" do
    api_get "/v1/spending/#{G2}", expand: "raw"
    assert_conforms("getSpendingRecord", status: 200)
    assert body["data"].key?("raw")
    assert_nil body.dig("data", "raw")
    assert_includes body.dig("meta", "caveats").map { |c| c["code"] }, "raw_unavailable"
    api_get "/v1/spending", fields: "amount,fiscal_year", limit: 2
    assert_conforms("listSpending", status: 200, projected: true)
    assert(body["data"].all? { |r| r.keys == %w[id amount fiscal_year cite] })
  end

  test "French cites and caveat text with Accept-Language: fr" do
    api_get "/v1/spending/#{G1_A0}", headers: { "Accept-Language" => "fr-CA,fr;q=0.9,en;q=0.5" }
    assert_conforms("getSpendingRecord", status: 200)
    assert_includes body.dig("data", "cite"), "Données de Build Canada, version 11"
    assert_equal "Les montants de proactive_grants sont des valeurs d'accord, pas des sommes versées.",
      body.dig("meta", "caveats").find { |c| c["code"] == "agreement_value_not_paid" }["text"]
    french = response.headers["ETag"]
    api_get "/v1/spending/#{G1_A0}"
    refute_equal french, response.headers["ETag"], "the ETag covers the language"
    assert_includes response.headers["Vary"], "Accept-Language"
  end

  test "spending sources: each source's meaning of amount and pinned snapshot" do
    api_get "/v1/spending/sources"
    assert_conforms("listSpendingSources", status: 200)
    assert_equal %w[global_affairs_projects proactive_contracts proactive_grants transfer_payments], body["data"].map { |s| s["source"] }
    grants = body["data"].find { |s| s["source"] == "proactive_grants" }
    assert_equal SNAPSHOTS[11][GRANTS], grants["snapshot_id"]
    assert_equal "agreement_value for that amendment. Do not sum across rows sharing a canonical_id.", grants["amount_note"]
    assert_equal "Hash of owner_org and ref_number.", grants["revisions_note"]
    assert_equal "/v1/spending?source=proactive_grants&as_of=11", grants.dig("links", "records")
  end

  private

  def page_through(path, **params)
    seen = []
    cursor = nil
    loop do
      api_get path, **params, **(cursor ? { cursor: } : {})
      assert_conforms("listSpending", status: 200)
      seen.concat(ids.map { |id| id.split("/").last })
      cursor = next_cursor or break
    end
    seen
  end
end
