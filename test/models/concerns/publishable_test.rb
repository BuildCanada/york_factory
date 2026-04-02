require "test_helper"

class PublishableTest < ActiveSupport::TestCase
  test "published scope returns records with past published_at" do
    published = Memo.published
    published.each do |m|
      assert m.published_at.present?
      assert m.published_at <= Time.current
    end
  end

  test "draft scope returns records without published_at" do
    drafts = Memo.draft
    drafts.each do |m|
      assert(m.published_at.nil? || m.published_at > Time.current)
    end
  end

  test "published? returns true for past published_at" do
    memo = memos(:published_memo)
    assert memo.published?
  end

  test "published? returns false for nil published_at" do
    memo = memos(:draft_memo)
    assert_not memo.published?
  end

  test "draft? returns true for nil published_at" do
    memo = memos(:draft_memo)
    assert memo.draft?
  end

  test "publish_status returns correct states" do
    assert_equal "published", memos(:published_memo).publish_status
    assert_equal "draft", memos(:draft_memo).publish_status
  end
end
