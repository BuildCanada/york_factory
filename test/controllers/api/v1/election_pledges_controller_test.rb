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
    @election.update!(published_at: 1.day.ago)
    Warehouse::PledgeToVote.where(election: @election).delete_all

    brampton = Warehouse::Jurisdiction.find_or_create_by!(slug: "brampton") do |j|
      j.name = "City of Brampton"
      j.code = "BRM-ON"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @brampton_election = Warehouse::Election.find_or_create_by!(slug: "brampton-2026") do |e|
      e.jurisdiction = brampton
      e.name = "Brampton 2026 General Municipal Election"
      e.kind = "municipal"
      e.election_date = Date.new(2026, 10, 26)
    end
    @brampton_election.update!(published_at: 1.day.ago)
    Warehouse::PledgeToVote.where(election: @brampton_election).delete_all

    # Residency is judged against the postal-code table, so the regions under
    # test need data in it.
    [ [ "L6Y 1A1", "BRAMPTON" ], [ "L5B 1M2", "MISSISSAUGA" ], [ "M5V 1A1", "TORONTO" ] ].each do |code, city|
      Warehouse::PostalCode.find_or_create_by!(postal_code: code) do |pc|
        pc.city = city
        pc.province_code = "ON"
        pc.latitude = 43.7
        pc.longitude = -79.7
      end
    end
  end

  test "a pledge in another region is accepted for a resident of that region" do
    post api_v1_election_pledges_url("brampton-2026"),
      params: { email: "resident@example.com", name: "Rita Resident", region: "wards-1-5", postal_code: "L6Y 1A1" }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "wards-1-5", body["region"]
    assert_equal 1, @brampton_election.pledges_to_vote.count
  end

  test "a Toronto postal code cannot pledge in Brampton" do
    post api_v1_election_pledges_url("brampton-2026"),
      params: { email: "outsider@example.com", name: "Otto Outsider", region: "wards-1-5", postal_code: "M5V 1A1" }

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal true, body["outside_region"]
    assert_equal "City of Brampton", body["region_name"]
    assert_equal "city_mismatch", body["reason"]
    assert_equal false, body["unverified_postal_code"]
    # The Toronto-only key stays false for other regions.
    assert_equal false, body["outside_toronto"]
    assert_equal true, body["subscribed"]
    assert_equal 0, @brampton_election.pledges_to_vote.count
    # The email is still kept as a newsletter signup.
    assert Subscriber.exists?(email: "outsider@example.com")
  end

  test "an unrecognized postal code is reported as unverified rather than outside" do
    post api_v1_election_pledges_url("brampton-2026"),
      params: { email: "newbuild@example.com", name: "Nina Newbuild", region: "wards-1-5", postal_code: "L6Y 9Z9" }

    body = JSON.parse(response.body)
    assert_equal true, body["outside_region"]
    assert_equal "unknown_postal_code", body["reason"]
    assert_equal true, body["unverified_postal_code"]
  end

  test "eligibility reports a resident as eligible without asking for an email" do
    assert_no_difference "Subscriber.count" do
      get eligibility_api_v1_election_pledges_url("brampton-2026"), params: { postal_code: "l6y1a1" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["eligible"]
    assert_equal "city_match", body["reason"]
    assert_equal "L6Y 1A1", body["postal_code"]
    assert_equal "BRAMPTON", body["city"]
    assert_equal "City of Brampton", body["region_name"]
    assert_equal true, body["gated"]
  end

  test "eligibility reports someone outside the region" do
    get eligibility_api_v1_election_pledges_url("brampton-2026"), params: { postal_code: "L5B 1M2" }

    body = JSON.parse(response.body)
    assert_equal false, body["eligible"]
    assert_equal "city_mismatch", body["reason"]
  end

  test "eligibility on an unknown election is a 404" do
    get eligibility_api_v1_election_pledges_url("nowhere-2026"), params: { postal_code: "M5V 1A1" }

    assert_response :not_found
  end

  test "a draft election takes no pledges and reports no eligibility" do
    @brampton_election.update!(published_at: nil)

    post api_v1_election_pledges_url("brampton-2026"),
      params: { email: "early@example.com", name: "Ellie Early", region: "wards-1-5", postal_code: "L6Y 1A1" }
    assert_response :not_found
    assert_equal 0, @brampton_election.pledges_to_vote.count
    refute Subscriber.exists?(email: "early@example.com")

    get eligibility_api_v1_election_pledges_url("brampton-2026"), params: { postal_code: "L6Y 1A1" }
    assert_response :not_found
  end

  test "create records a pledge and signs the email up as a subscriber" do
    freeze_time do
      assert_difference "Subscriber.count", 1 do
        post api_v1_election_pledges_url("toronto-2026"),
          params: { email: "voter@example.com", name: "Jane Q Voter", region: "ward-5", postal_code: "M5V 1A1" }
      end

      assert_response :created
      body = JSON.parse(response.body)
      assert_equal "ward-5", body["region"]
      assert_equal 1, body["region_count"]

      subscriber = Subscriber.find_by!(email: "voter@example.com")
      assert_equal "Jane Q", subscriber.first_name
      assert_equal "Voter", subscriber.last_name
      assert_equal "M5V 1A1", subscriber.postal_code

      assert_equal "Jane Q Voter", body["name"]
      assert_match(/\A[a-z0-9]{10}\z/, body["share_token"])

      pledge = Warehouse::PledgeToVote.where(election: @election).sole
      assert_equal subscriber.id, pledge.subscriber_id
      assert_equal Time.current, pledge.pledged_at
    end
  end

  test "create stamps the subscriber's pledged_to_vote_at" do
    freeze_time do
      post api_v1_election_pledges_url("toronto-2026"),
        params: { email: "voter@example.com", name: "Jane Q Voter", region: "ward-5", postal_code: "M5V 1A1" }

      assert_response :created
      subscriber = Subscriber.find_by!(email: "voter@example.com")
      assert_equal Time.current, subscriber.pledged_to_vote_at
    end
  end

  test "create submits the pledge form once, never the subscriber form" do
    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", name: "Jane Voter", region: "ward-5", postal_code: "M5V 1A1" }

    assert_response :created
    subscriber = Subscriber.find_by!(email: "voter@example.com")
    assert_enqueued_with(job: Subscriber::SubmitToHubspotFormJob, args: [ subscriber, :pledge ])

    form_jobs = enqueued_jobs.select { |job| job["job_class"] == "Subscriber::SubmitToHubspotFormJob" }
    assert_equal 1, form_jobs.size
  end

  test "an out-of-region signup submits the subscriber form, not the pledge form" do
    post api_v1_election_pledges_url("brampton-2026"),
      params: { email: "outsider@example.com", name: "Otto Outsider", region: "wards-1-5", postal_code: "M5V 1A1" }

    assert_response :ok
    subscriber = Subscriber.find_by!(email: "outsider@example.com")
    assert_enqueued_with(job: Subscriber::SubmitToHubspotFormJob, args: [ subscriber ])

    form_jobs = enqueued_jobs.select { |job| job["job_class"] == "Subscriber::SubmitToHubspotFormJob" }
    assert_equal 1, form_jobs.size
  end

  test "create stores the pledge source and tracking context on the subscriber" do
    post api_v1_election_pledges_url("toronto-2026"),
      params: {
        email: "voter@example.com", name: "Jane Voter", region: "ward-5", postal_code: "M5V 1A1",
        page_uri: "https://buildcanada.com/elections/toronto-2026",
        page_name: "Toronto 2026", hubspot_utk: "utk-cookie", ip_address: "203.0.113.7"
      }

    assert_response :created
    subscriber = Subscriber.find_by!(email: "voter@example.com")
    assert_equal "pledge", subscriber.source
    assert_equal "https://buildcanada.com/elections/toronto-2026", subscriber.page_uri
    assert_equal "Toronto 2026", subscriber.page_name
    assert_equal "utk-cookie", subscriber.hubspot_utk
    assert_equal "203.0.113.7", subscriber.ip_address
  end

  test "create rejects a missing name, single-word name, or missing postal code" do
    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", region: "ward-5", postal_code: "M5V 1A1" }
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Full name (first and last) is required"

    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", name: "Cher", region: "ward-5", postal_code: "M5V 1A1" }
    assert_response :unprocessable_entity

    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", name: "Jane Voter", region: "ward-5" }
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Postal code is required"

    assert_equal 0, Warehouse::PledgeToVote.where(election: @election).count
    assert_nil Subscriber.find_by(email: "voter@example.com")
  end

  test "create reuses an existing subscriber without overwriting their name or postal code" do
    existing = Subscriber.create!(
      email: "voter@example.com", first_name: "Jane", last_name: "Voter", postal_code: "M4B 1B3"
    )

    assert_no_difference "Subscriber.count" do
      post api_v1_election_pledges_url("toronto-2026"),
        params: { email: "Voter@Example.COM", name: "Different Name", region: "toronto", postal_code: "M6H 2K2" }
    end

    assert_response :created
    assert_equal "Jane", existing.reload.first_name
    assert_equal "M4B 1B3", existing.postal_code
    pledge = Warehouse::PledgeToVote.where(election: @election).sole
    assert_equal existing.id, pledge.subscriber_id
  end

  test "create fills in a blank postal code on an existing subscriber" do
    existing = Subscriber.create!(email: "voter@example.com", first_name: "Jane", last_name: "Voter")

    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", name: "Jane Voter", region: "toronto", postal_code: "m5v 1a1" }

    assert_response :created
    assert_equal "M5V 1A1", existing.reload.postal_code
  end

  test "re-pledging updates the existing pledge instead of duplicating" do
    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", name: "Jane Voter", region: "ward-5", postal_code: "M5V 1A1" }
    assert_response :created

    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", name: "Jane Voter", region: "toronto", postal_code: "M5V 1A1" }
    assert_response :ok

    pledge = Warehouse::PledgeToVote.where(election: @election).sole
    assert_equal "toronto", pledge.region
  end

  test "create signs up an out-of-Toronto pledger as a subscriber but records no pledge" do
    assert_difference "Subscriber.count", 1 do
      post api_v1_election_pledges_url("toronto-2026"),
        params: { email: "outsider@example.com", name: "Otto Outsider", region: "toronto", postal_code: "L5B 1M2" }
    end

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal true, body["outside_toronto"]
    assert_equal true, body["subscribed"]
    assert_equal "Otto Outsider", body["name"]
    assert_nil body["share_token"]

    subscriber = Subscriber.find_by!(email: "outsider@example.com")
    assert_equal "L5B 1M2", subscriber.postal_code
    assert_equal 0, Warehouse::PledgeToVote.where(election: @election).count
  end

  test "create treats a lowercase Toronto postal code as inside the city" do
    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", name: "Jane Voter", region: "toronto", postal_code: "m4b 1b3" }

    assert_response :created
    assert_equal 1, Warehouse::PledgeToVote.where(election: @election).count
  end

  test "create rejects a missing or invalid email" do
    post api_v1_election_pledges_url("toronto-2026"),
      params: { name: "Jane Voter", region: "ward-5", postal_code: "M5V 1A1" }
    assert_response :unprocessable_entity

    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "not-an-email", name: "Jane Voter", region: "ward-5", postal_code: "M5V 1A1" }
    assert_response :unprocessable_entity

    assert_equal 0, Warehouse::PledgeToVote.where(election: @election).count
  end

  test "create rejects a missing region" do
    post api_v1_election_pledges_url("toronto-2026"),
      params: { email: "voter@example.com", name: "Jane Voter", postal_code: "M5V 1A1" }

    assert_response :unprocessable_entity
    assert_equal 0, Warehouse::PledgeToVote.where(election: @election).count
  end

  test "show returns a pledge by share token without exposing the email" do
    subscriber = Subscriber.create!(email: "voter@example.com", first_name: "Jane", last_name: "Voter")
    pledge = @election.pledges_to_vote.create!(subscriber: subscriber, region: "ward-5")

    get api_v1_election_pledge_url("toronto-2026", pledge.share_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Jane Voter", body["name"]
    assert_equal "ward-5", body["region"]
    assert_nil body["email"]
  end

  test "show returns 404 for an unknown share token" do
    get api_v1_election_pledge_url("toronto-2026", "nope123456")
    assert_response :not_found
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
