require "test_helper"

class Admin::TradeBarriers::AgreementsControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    @theme = TradeBarriers::Theme.find_or_create_by!(name: "Goods")
    Warehouse::Jurisdiction.find_or_create_by!(code: "AB") do |j|
      j.name = "Alberta"; j.level = "provincial"
    end
  end

  test "redirects unauthenticated users" do
    get admin_trade_barriers_agreements_url
    assert_redirected_to new_user_session_path
  end

  test "redirects member users" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    get admin_trade_barriers_agreements_url
    assert_redirected_to new_user_session_path
  end

  test "admin can list agreements" do
    sign_in_admin
    get admin_trade_barriers_agreements_url
    assert_response :success
  end

  test "admin can create an agreement" do
    sign_in_admin
    assert_difference -> { TradeBarriers::Agreement.count }, 1 do
      post admin_trade_barriers_agreements_url, params: {
        trade_barriers_agreement: {
          title: "New Agreement",
          summary: "summary",
          description: "desc",
          status: "awaiting_sponsorship",
          theme_id: @theme.id
        }
      }
    end
  end
end
