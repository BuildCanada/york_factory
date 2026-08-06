require "test_helper"

class Warehouse::Spending::SearchTest < ActiveSupport::TestCase
  setup do
    @contracts = source("spending_proactive_contracts")
    @grants = source("spending_cihr_awards")
    @contract = award(
      @contracts,
      external_key: "contract-1",
      award_type: "contract",
      title: "Cloud services",
      description: "Secure cloud hosting",
      payer_name: "Shared Services Canada",
      recipient_name: "Example Cloud Inc.",
      program_name: "Infrastructure",
      fiscal_year: 2024,
      amount: 500_000,
      province_code: "ON"
    )
    @grant = award(
      @grants,
      external_key: "grant-1",
      award_type: "grant",
      title: "Cancer research",
      description: "Clinical research program",
      payer_name: "Canadian Institutes of Health Research",
      recipient_name: "University of Alberta",
      program_name: "Project Grant",
      fiscal_year: 2023,
      amount: 125_000,
      province_code: "AB"
    )
  end

  test "searches, filters, sorts, paginates, and returns facet counts" do
    result = Warehouse::Spending::Search.new(
      q: "research",
      filter_by: "award_type:=[`grant`] && province:=[`Alberta`]",
      facet_by: "payer,fiscal_year,award_type",
      sort_by: "amount:desc",
      page: 1,
      per_page: 25
    ).call

    assert_equal [ @grant ], result.records
    assert_equal 1, result.found
    assert_equal [ { value: "2023-2024", count: 1, highlighted: "2023-2024" } ], result.facets.fetch("fiscal_year")
    assert_equal "grant", result.facets.fetch("award_type").sole.fetch(:value)
  end

  test "supports disjunctive values, amount ordering, and stable pages" do
    result = Warehouse::Spending::Search.new(
      filter_by: "payer:=[`Shared Services Canada`,`Canadian Institutes of Health Research`]",
      sort_by: "amount:asc",
      page: 2,
      per_page: 1
    ).call

    assert_equal 2, result.found
    assert_equal [ @contract ], result.records
  end

  test "facet queries return matching values without hits" do
    result = Warehouse::Spending::Search.new(
      q: "*",
      facet_by: "payer",
      facet_query: "payer:shared",
      per_page: 0
    ).call

    assert_empty result.records
    count = result.facets.fetch("payer").sole
    assert_equal "Shared Services Canada", count.fetch(:value)
    assert_includes count.fetch(:highlighted), "<mark>Shared</mark>"
  end

  test "rejects unknown filters and sort fields" do
    assert_raises(Warehouse::Spending::Search::InvalidRequest) do
      Warehouse::Spending::Search.new(filter_by: "secret:=[x]").call
    end
    assert_raises(Warehouse::Spending::Search::InvalidRequest) do
      Warehouse::Spending::Search.new(sort_by: "created_at:desc").call
    end
  end

  private

  def source(name)
    Warehouse::Source.create!(name:, url: "https://example.test/#{name}", format: "csv")
  end

  def award(source, attributes)
    now = Time.current
    Warehouse::SpendingAward.create!({
      source:,
      external_key: SecureRandom.hex(8),
      award_type: "grant",
      title: "Award",
      occurred_at: Time.zone.parse("2024-04-01"),
      currency: "CAD",
      first_seen_at: now,
      last_seen_at: now
    }.merge(attributes))
  end
end
