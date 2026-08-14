require "test_helper"

class Admin::EndorsementsControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    sign_in_admin
    @memo  = memos(:published_memo)
    @other = memos(:build_toronto_memo)
    @endorsement = Endorsement.create!(memo: @memo, user: users(:member))
  end

  # Auth guard
  test "unauthenticated access redirects to login" do
    delete destroy_user_session_path
    get admin_endorsements_path
    assert_redirected_to new_user_session_path
  end

  test "member cannot access admin endorsements" do
    delete destroy_user_session_path
    post user_session_path, params: { email: users(:member).email, password: "password123" }
    get admin_endorsements_path
    assert_response :redirect
  end

  # Index
  test "index lists endorsements" do
    get admin_endorsements_path
    assert_response :success
    assert_select "table tbody tr", 1
    assert_select "td", /Member User/
  end

  test "index filters by memo" do
    Endorsement.create!(memo: @other, user: users(:regular))

    get admin_endorsements_path
    assert_response :success
    assert_select "table tbody tr", 2

    get admin_endorsements_path, params: { memo_id: @memo.id }
    assert_response :success
    assert_select "table tbody tr", 1
    assert_select "td", @memo.title_en
  end

  test "index header total follows the memo filter" do
    Endorsement.create!(memo: @other, user: users(:regular))

    get admin_endorsements_path
    assert_select ".page-header strong", "2"

    get admin_endorsements_path, params: { memo_id: @memo.id }
    assert_select ".page-header strong", "1"
  end

  test "index renders an empty state with no endorsements" do
    Endorsement.destroy_all
    get admin_endorsements_path
    assert_response :success
    assert_select ".empty"
  end

  # Show
  test "show renders" do
    get admin_endorsement_path(@endorsement)
    assert_response :success
    assert_select "h1", "Endorsement ##{@endorsement.id}"
  end

  # Destroy
  test "destroy removes the endorsement and decrements the memo counter" do
    assert_difference -> { @memo.reload.endorsements_count }, -1 do
      assert_difference -> { Endorsement.count }, -1 do
        delete admin_endorsement_path(@endorsement)
      end
    end
    assert_redirected_to admin_endorsements_path(memo_id: @memo.id)
    assert_equal "Endorsement removed.", flash[:notice]
  end

  test "destroy leaves critiques on the same memo alone" do
    critique = Critique.create!(memo: @memo, user: users(:regular), body: "Still stands.")
    delete admin_endorsement_path(@endorsement)
    assert Critique.exists?(critique.id)
  end
end
