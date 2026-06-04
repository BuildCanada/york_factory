require "test_helper"

class Admin::TradeBarriers::AgreementsControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    @theme = TradeBarriers::Theme.find_or_create_by!(name: "Goods")
    Warehouse::Jurisdiction.find_or_create_by!(code: "AB") do |j|
      j.name = "Alberta"; j.slug = "ab"; j.level = "provincial"; j.fiscal_year_start_month = 4
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

  test "admin can render the new agreement form" do
    sign_in_admin
    get new_admin_trade_barriers_agreement_url
    assert_response :success
  end

  test "admin can render the edit agreement form" do
    sign_in_admin
    agreement = TradeBarriers::Agreement.create!(
      title: "Existing Agreement",
      status: "awaiting_sponsorship",
      theme: @theme
    )
    get edit_admin_trade_barriers_agreement_url(agreement)
    assert_response :success
  end

  test "admin can update an agreement" do
    sign_in_admin
    agreement = TradeBarriers::Agreement.create!(
      title: "Existing Agreement",
      status: "awaiting_sponsorship",
      theme: @theme
    )
    patch admin_trade_barriers_agreement_url(agreement), params: {
      trade_barriers_agreement: { title: "Updated Agreement" }
    }
    assert_redirected_to admin_trade_barriers_agreement_url(agreement)
    assert_equal "Updated Agreement", agreement.reload.title
  end
end
