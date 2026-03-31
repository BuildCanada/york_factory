require "test_helper"

class ToolTest < ActiveSupport::TestCase
  test "validates size inclusion" do
    tool = Tool.new(size: "invalid")
    assert_not tool.valid?
    assert_includes tool.errors[:size], "is not included in the list"
  end

  test "allows valid sizes" do
    %w[small big].each do |size|
      tool = Tool.new(title_en: "Tool #{size}", size: size)
      assert tool.valid?, "Expected size '#{size}' to be valid"
    end
  end

  test "allows nil size" do
    tool = Tool.new(title_en: "No size tool")
    assert tool.valid?
  end

  test "featured scope returns featured tools" do
    featured = Tool.featured
    featured.each { |t| assert t.featured }
  end

  test "ordered scope sorts by position" do
    tools = Tool.ordered
    positions = tools.map(&:position).compact
    assert_equal positions, positions.sort
  end
end
