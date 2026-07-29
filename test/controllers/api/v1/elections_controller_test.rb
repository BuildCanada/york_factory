require "test_helper"

class Api::V1::ElectionsControllerTest < ActionDispatch::IntegrationTest
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
      e.nomination_close_date = Date.new(2026, 9, 18)
    end
    # The public API only serves published elections.
    @election.update!(published_at: 1.day.ago)

    mayor = @election.races.find_or_create_by!(office_type: "mayor", district_type: "at_large")
    mayor.candidates.find_or_create_by!(full_name: "Chow, Olivia") do |c|
      c.first_name = "Olivia"
      c.last_name = "Chow"
      c.status = "active"
      c.nomination_date = Date.new(2026, 5, 1)
      c.website = "https://oliviachow.ca"
      c.social_links = [ { "name" => "web", "url" => "https://oliviachow.ca" } ]
      c.email = "hello@oliviachow.ca"
      c.phone = "416-555-0100"
    end
    mayor.candidates.find_or_create_by!(full_name: "Abdulsalam, Bahira") do |c|
      c.first_name = "Bahira"
      c.last_name = "Abdulsalam"
      c.status = "active"
    end

    ward4 = @election.races.find_or_create_by!(
      office_type: "councillor", district_type: "ward", district_number: 4
    ) { |r| r.district_name = "Parkdale-High Park" }
    ward4.candidates.find_or_create_by!(full_name: "Nikolaou, Jonathan") do |c|
      c.first_name = "Jonathan"
      c.last_name = "Nikolaou"
      c.status = "withdrawn"
      c.withdrawn_date = Date.new(2026, 6, 3)
    end
  end

  test "index lists elections without races" do
    get api_v1_elections_url
    assert_response :success

    data = JSON.parse(response.body)["data"]
    election = data.find { |e| e["slug"] == "toronto-2026" }
    assert election
    assert_equal "Toronto 2026 General Municipal Election", election["name"]
    assert_equal "2026-10-26", election["election_date"]
    assert_equal "City of Toronto", election.dig("jurisdiction", "name")
    assert_nil election["races"]
  end

  test "show returns races sorted mayor-first with candidates sorted by last name" do
    get api_v1_election_url("toronto-2026")
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "toronto-2026", body["slug"]
    assert_equal "2026-09-18", body["nomination_close_date"]

    races = body["races"]
    assert_equal %w[mayor councillor], races.map { |r| r["office_type"] }
    assert_equal 4, races.last["district_number"]
    assert_equal "Parkdale-High Park", races.last["district_name"]

    mayor_candidates = races.first["candidates"]
    assert_equal [ "Abdulsalam, Bahira", "Chow, Olivia" ], mayor_candidates.map { |c| c["full_name"] }

    chow = mayor_candidates.last
    assert_equal "Olivia", chow["first_name"]
    assert_equal "active", chow["status"]
    assert_equal "https://oliviachow.ca", chow["website"]
    assert_equal 1, chow["social_links"].size

    withdrawn = races.last["candidates"].sole
    assert_equal "withdrawn", withdrawn["status"]
    assert_equal "2026-06-03", withdrawn["withdrawn_date"]
  end

  test "show includes photo_url when a photo is attached" do
    chow = Warehouse::ElectionCandidate.find_by!(full_name: "Chow, Olivia")
    chow.photo.attach(
      io: StringIO.new("fake image bytes"), filename: "olivia-chow.jpg", content_type: "image/jpeg"
    )
    chow.update!(photo_attribution: "Campaign photo")

    get api_v1_election_url("toronto-2026")

    candidates = JSON.parse(response.body)["races"].first["candidates"]
    with_photo = candidates.find { |c| c["full_name"] == "Chow, Olivia" }
    without_photo = candidates.find { |c| c["full_name"] == "Abdulsalam, Bahira" }

    assert with_photo["photo_url"].present?
    assert_equal "Campaign photo", with_photo["photo_attribution"]
    assert_nil without_photo["photo_url"]
  end

  test "a draft election is hidden from the index and show" do
    @election.update!(published_at: nil)

    get api_v1_elections_url
    assert_response :success
    assert_equal [], JSON.parse(response.body)["data"].map { |e| e["slug"] }

    get api_v1_election_url("toronto-2026")
    assert_response :not_found
    assert_equal "Not found", JSON.parse(response.body)["error"]
  end

  test "an election scheduled for the future is also hidden" do
    @election.update!(published_at: 1.week.from_now)

    get api_v1_election_url("toronto-2026")

    assert_response :not_found
  end

  test "an admin token previews a draft election" do
    @election.update!(published_at: nil)
    admin = users(:admin)
    admin.update!(role: "admin") unless admin.admin?
    application = Doorkeeper::Application.create!(name: "preview-#{SecureRandom.hex(4)}",
      redirect_uri: "https://example.com/cb")
    token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: admin.id)

    get api_v1_election_url("toronto-2026"), headers: { "Authorization" => "Bearer #{token.token}" }

    assert_response :success
    assert_equal "toronto-2026", JSON.parse(response.body)["slug"]
  end

  test "show excludes candidate email and phone" do
    get api_v1_election_url("toronto-2026")

    chow = JSON.parse(response.body)["races"].first["candidates"].last
    refute chow.key?("email")
    refute chow.key?("phone")
  end

  test "show returns 404 for unknown slugs" do
    get api_v1_election_url("atlantis-2026")
    assert_response :not_found
  end
end
