require "test_helper"

# All of fact-factory's data is public (decided 2026-09-30): values are served
# as the sources publish them, addresses and postal codes included, and person
# entities are read and listed like any other. What stays is correctness:
# individuals are kept out of organization matching, and an empty summary
# before any match rule is active is an answer, not an error.
class PublicApiPublishedDataTest < PublicApiTestCase
  test "an individual recipient's postal code is served as the source publishes it" do
    api_get "/v1/spending/#{G_PERSON}"
    assert_conforms("getSpendingRecord", status: 200)
    assert_equal "T2P 1J9", body.dig("data", "recipient_postal_code")
    assert_equal "individual", body.dig("data", "parties").find { |p| p["field"] == "recipient" }["party_kind"]
  end

  test "address attributes are served like any other attribute" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}"
    assert_conforms("getEntity", status: 200)
    assert_equal({ "municipality_type_raw" => "Town", "office" => { "mailing_address" => "Box 1, Diamond Valley" } }, body.dig("data", "attributes"))
    api_get "/v1/entities/#{DIAMOND_VALLEY}/relationships", predicate: "located_within", direction: "out"
    dguid = body["data"].find { |r| r["object_ref"] }
    assert_equal "1 Main St", dguid.dig("attributes", "street_address")
  end

  test "persons are listed like any entity" do
    api_get "/v1/entities", class: "person"
    assert_conforms("listEntities", status: 200)
    assert_equal [ "gid://buildcanada/Entity/#{PERSON}" ], ids
    assert_cache_control "public, max-age=300, stale-while-revalidate=3600"
  end

  test "individuals are kept out of organization matching: never an unlinked candidate of an organization" do
    api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/unlinked", limit: 200
    assert_conforms("listEntityUnlinkedSpending", status: 200)
    refute(body["data"].any? { |o| o.dig("party", "party_kind") == "individual" })
  end

  test "an entity with nothing linked has an empty summary, with a caveat that says why" do
    api_get "/v1/entities/#{NEW}/spending/summary"
    assert_conforms("getEntitySpendingSummary", status: 200)
    assert_empty body["data"]
    assert_equal [ 0, 0 ], body["meta"].values_at("aggregated_rows_excluded", "unlinked_occurrences")
    assert_includes body.dig("meta", "caveats").map { |c| c["code"] }, "nothing_linked"
    api_get "/v1/entities/#{NEW}/spending/summary", group_by: "counterparty"
    assert_conforms("getEntitySpendingSummary", status: 200)
    assert_empty body["data"]
  end

  test "with no summary rows at all, as before any match rule is active, every summary is empty" do
    FactFactory::SpendingQuery.stub_any_instance(:summary, []) do
      api_get "/v1/entities/#{DIAMOND_VALLEY}/spending/summary"
    end
    assert_conforms("getEntitySpendingSummary", status: 200)
    assert_empty body["data"]
    assert_includes body.dig("meta", "caveats").map { |c| c["code"] }, "nothing_linked"
  end
end

module StubAnyInstance
  # Replaces an instance method of a class for the block.
  def stub_any_instance(name, value)
    original = instance_method(name)
    define_method(name) { |*, **| value }
    yield
  ensure
    define_method(name, original)
  end
end
FactFactory::SpendingQuery.extend(StubAnyInstance)
