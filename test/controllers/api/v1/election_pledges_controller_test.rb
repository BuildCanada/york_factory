require "test_helper"

class Api::V1::ElectionPledgesControllerTest < ActionDispatch::IntegrationTest
  setup do
    toronto = Warehouse::Jurisdiction.find_or_create_by!(slug: "toronto") do |j|
      j.name = "City of Toronto"
      j.code = "TOR-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @election = Warehouse::Election.find_or_create_by!(slug: "toronto-2026") do |e|
      e.jurisdiction = toronto
      e.name = "Toronto 2026 General Municipal Election"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
    end
    Warehouse::PledgeToVote.where(election: @election).delete_all
  end

  test "create records a pledge and signs the email up as a subscriber" do
    freeze_time do
      assert_difference "Subscriber.count", 1 do
        post api_v1_election_pledges_url("toronto-2026"),
          params: { email: "voter@example.com", name: "Jane Q Voter", region: "ward-5" }
      end

      assert_response :created
      body = JSON.parse(response.body)
      assert_equal "ward-5", body["region"]
      assert_equal 1, body["region_count"]

      subscriber = Subscriber.find_by!(email: "voter@example.com")
      assert_equal "Jane Q", subscriber.first_name
      assert_equal "Voter", subscriber.last_name

      pledge = Warehouse::PledgeToVote.where(election: @election).sole
      assert_equal subscriber.id, pledge.subscriber_id
      assert_equal Time.current, pledge.pledged_at
    end
  end

  test "create reuses an existing subscriber without overwriting their name" do
    existing = Subscriber.create!(email: "voter@example.com", first_name: "Jane", last_name: "Voter")

    assert_no_difference "Subscriber.count" do
      post api_v1_election_pledges_url("toronto-2026"),
        params: { email: "Voter@Example.COM", name: "Different Name", region: "toronto" }
    end

    assert_response :created
    assert_equal "Jane", existing.reload.first_name
    pledge = Warehouse::PledgeToVote.where(election: @election).sole
    assert_equal existing.id, pledge.subscriber_id
  end

  test "re-pledging updates the existing pledge instead of duplicating" do
    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", region: "ward-5" }
    assert_response :created

    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", region: "toronto" }
    assert_response :ok

    pledge = Warehouse::PledgeToVote.where(election: @election).sole
    assert_equal "toronto", pledge.region
  end

  test "create rejects a missing or invalid email" do
    post api_v1_election_pledges_url("toronto-2026"), params: { region: "ward-5" }
    assert_response :unprocessable_entity

    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "not-an-email", region: "ward-5" }
    assert_response :unprocessable_entity

    assert_equal 0, Warehouse::PledgeToVote.where(election: @election).count
  end

  test "create rejects a missing region" do
    post api_v1_election_pledges_url("toronto-2026"), params: { email: "voter@example.com" }

    assert_response :unprocessable_entity
    assert_equal 0, Warehouse::PledgeToVote.where(election: @election).count
  end

  test "index returns counts by region and a total" do
    a = Subscriber.create!(email: "a@example.com")
    b = Subscriber.create!(email: "b@example.com")
    @election.pledges_to_vote.create!(subscriber: a, region: "ward-5")
    @election.pledges_to_vote.create!(subscriber: b, region: "toronto")

    get api_v1_election_pledges_url("toronto-2026")

    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert_equal 2, data["total"]
    assert_equal({ "ward-5" => 1, "toronto" => 1 }, data["by_region"])
  end

  test "returns 404 for unknown elections" do
    post api_v1_election_pledges_url("atlantis-2026"),
      params: { email: "voter@example.com", region: "ward-1" }
    assert_response :not_found
  end
end
