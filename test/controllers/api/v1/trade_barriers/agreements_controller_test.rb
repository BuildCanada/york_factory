require "test_helper"

class Api::V1::TradeBarriers::AgreementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @theme = TradeBarriers::Theme.find_or_create_by!(name: "Goods")
    @ab = Warehouse::Jurisdiction.find_or_create_by!(code: "AB") do |j|
      j.name = "Alberta"; j.level = "provincial"
    end
    @agreement = TradeBarriers::Agreement.create!(
      title: "Test Agreement",
      summary: "A summary",
      description: "A longer description",
      status: "agreement_reached",
      theme: @theme
    )
    @agreement.agreement_jurisdictions.create!(
      jurisdiction: @ab, status: "committed", notes: "Signed"
    )
    @agreement.histories.create!(status: "under_negotiation", date_entered: Date.new(2025, 6, 30))
  end

  test "index returns a list with embedded jurisdictions and history" do
    get api_v1_trade_barriers_agreements_url
    assert_response :success
    data = JSON.parse(response.body)["data"]
    row = data.find { |a| a["slug"] == @agreement.slug }
    assert row
    assert_equal "agreement_reached", row["status"]
    assert_equal "Goods", row["theme"]["name"]
    assert_equal 1, row["jurisdictions"].size
    assert_equal "AB", row["jurisdictions"].first["code"]
    assert_equal 1, row["history"].size
  end

  test "show returns description and per-jurisdiction history" do
    get api_v1_trade_barriers_agreement_url(slug: @agreement.slug)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @agreement.description, body["description"]
    assert body["jurisdictions"].first.key?("history")
  end

  test "show returns 404 for unknown slug" do
    get api_v1_trade_barriers_agreement_url(slug: "does-not-exist")
    assert_response :not_found
  end
end
