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

  test "webflow_published_at returns parsed lastPublished when item is published" do
    svc = instantiate
    item = { "lastPublished" => "2026-04-01T12:00:00Z", "isDraft" => false, "isArchived" => false }

    assert_equal Time.zone.parse("2026-04-01T12:00:00Z"), svc.send(:webflow_published_at, item)
  end

  test "webflow_published_at returns nil for draft items (so they stay draft locally)" do
    svc = instantiate
    draft     = { "lastPublished" => nil, "isDraft" => true,  "isArchived" => false }
    never_pub = { "lastPublished" => nil, "isDraft" => false, "isArchived" => false }
    archived  = { "lastPublished" => "2026-04-01T12:00:00Z", "isDraft" => false, "isArchived" => true }

    assert_nil svc.send(:webflow_published_at, draft)
    assert_nil svc.send(:webflow_published_at, never_pub)
    assert_nil svc.send(:webflow_published_at, archived)
  end

  test "webflow_archived? flags archived items for skip" do
    svc = instantiate
    assert svc.send(:webflow_archived?, { "isArchived" => true })
    refute svc.send(:webflow_archived?, { "isArchived" => false })
    refute svc.send(:webflow_archived?, {})
  end
end
