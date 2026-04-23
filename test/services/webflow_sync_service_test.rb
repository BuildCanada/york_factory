require "test_helper"

class WebflowSyncServiceTest < ActiveSupport::TestCase
  # The reclassify_memo_authors step should promote any team member who
  # authors a memo — as long as they don't hold a preserved role — to the
  # memo_author role. Preserved roles are board, advisor, volunteer.
  #
  # The method is private and invoked by sync!; we call it directly via
  # .send to avoid hitting the Webflow API in tests.

  def instantiate
    WebflowSyncService.allocate.tap do |svc|
      svc.instance_variable_set(:@errors, [])
      svc.instance_variable_set(:@team_id_map, {})
    end
  end

  test "reclassifies an employee who authors a memo into memo_author" do
    author = team_members(:alice)
    author.update_column(:role, "employee")
    # alice authors :published_memo in fixtures

    count = instantiate.send(:reclassify_memo_authors)

    assert_operator count, :>=, 1
    assert_equal "memo_author", author.reload.role
  end

  test "preserves board/advisor/volunteer roles even when they author memos" do
    author = team_members(:alice)
    author.update_column(:role, "board")

    instantiate.send(:reclassify_memo_authors)

    assert_equal "board", author.reload.role
  end

  test "does not touch team members who never author a memo" do
    non_author = TeamMember.create!(name: "Not An Author", role: "employee")

    instantiate.send(:reclassify_memo_authors)

    assert_equal "employee", non_author.reload.role
  end

  test "is idempotent — memo_authors stay memo_author" do
    author = team_members(:alice)
    author.update_column(:role, "memo_author")

    instantiate.send(:reclassify_memo_authors)

    assert_equal "memo_author", author.reload.role
  end
end
