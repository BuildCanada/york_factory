require "test_helper"

class Admin::TradeBarriers::ThemesControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  test "admin can list themes" do
    sign_in_admin
    get admin_trade_barriers_themes_url
    assert_response :success
  end

  test "admin can render the new theme form" do
    sign_in_admin
    get new_admin_trade_barriers_theme_url
    assert_response :success
  end

  test "admin can render the edit theme form" do
    sign_in_admin
    theme = TradeBarriers::Theme.find_or_create_by!(name: "Goods")
    get edit_admin_trade_barriers_theme_url(theme)
    assert_response :success
  end

  test "admin can create a theme" do
    sign_in_admin
    assert_difference -> { TradeBarriers::Theme.count }, 1 do
      post admin_trade_barriers_themes_url, params: {
        trade_barriers_theme: { name: "Services" }
      }
    end
    assert_redirected_to admin_trade_barriers_themes_url
  end

  test "admin can update a theme" do
    sign_in_admin
    theme = TradeBarriers::Theme.find_or_create_by!(name: "Goods")
    patch admin_trade_barriers_theme_url(theme), params: {
      trade_barriers_theme: { name: "Renamed" }
    }
    assert_redirected_to admin_trade_barriers_themes_url
    assert_equal "Renamed", theme.reload.name
  end
end
