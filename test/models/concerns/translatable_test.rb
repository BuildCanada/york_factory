require "test_helper"

class TranslatableTest < ActiveSupport::TestCase
  test "hash_fields DSL registers fields" do
    assert_includes Memo.hash_fields, :key_messages
  end

  test "hash_fields returns empty array when none declared" do
    assert_equal [], TeamMember.hash_fields
  end

  test "translatable_fields DSL registers fields" do
    assert_includes Memo.translatable_fields, :title
    assert_not_includes Memo.translatable_fields, :key_messages
  end

  test "markdown_fields DSL registers fields" do
    assert_includes Memo.markdown_fields, :body
    assert_includes Memo.markdown_fields, :appendix
    assert_includes Memo.markdown_fields, :supporters
  end
end
