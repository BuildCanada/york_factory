require "test_helper"

class EngagementTest < ActiveSupport::TestCase
  setup do
    @memo  = memos(:published_memo)
    @user  = users(:member)
    @other = users(:regular)
    @admin = users(:admin)
  end

  test "endorsement belongs to a user and delegates author identity" do
    e = Endorsement.create!(memo: @memo, user: @user)
    assert_equal @user.name, e.author_name
    assert_equal @user.postal_code, e.author_postal_code
  end

  test "endorsements are auto-approved" do
    assert Endorsement.create!(memo: @memo, user: @user).approved?
  end

  test "a user can endorse a given memo only once" do
    Endorsement.create!(memo: @memo, user: @user)
    dup = Endorsement.new(memo: @memo, user: @user)
    assert_not dup.valid?
    assert dup.errors.where(:user_id, :taken).any?
  end

  test "different users can each endorse the same memo" do
    Endorsement.create!(memo: @memo, user: @user)
    assert Endorsement.new(memo: @memo, user: @other).valid?
  end

  test "a user can both endorse and critique the same memo" do
    Endorsement.create!(memo: @memo, user: @user)
    critique = Critique.new(memo: @memo, user: @user, body: "Thoughtful pushback here.")
    assert critique.valid?, critique.errors.full_messages.to_sentence
  end

  test "endorsing increments the memo endorsements counter cache" do
    assert_difference -> { @memo.reload.endorsements_count }, 1 do
      Endorsement.create!(memo: @memo, user: @user)
    end
  end

  test "approving and rejecting a critique drives approved_critiques_count" do
    critique = Critique.create!(memo: @memo, user: @user, body: "Pending by default.")
    assert_equal 0, @memo.reload.approved_critiques_count

    critique.approve!(@admin)
    assert_equal 1, @memo.reload.approved_critiques_count
    assert_equal @admin, critique.moderated_by

    critique.reject!(@admin)
    assert_equal 0, @memo.reload.approved_critiques_count
  end

  test "critique requires a body" do
    critique = Critique.new(memo: @memo, user: @user)
    assert_not critique.valid?
    assert critique.errors.where(:body, :blank).any?
  end

  test "critique defaults to pending" do
    assert Critique.create!(memo: @memo, user: @user, body: "Some critique.").pending?
  end
end
