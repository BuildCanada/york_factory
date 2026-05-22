require "test_helper"

class TradeBarriers::ThemeTest < ActiveSupport::TestCase
  test "name is required and unique" do
    TradeBarriers::Theme.find_or_create_by!(name: "Goods")
    duplicate = TradeBarriers::Theme.new(name: "Goods")
    assert_not duplicate.valid?
    assert duplicate.errors[:name].any?
  end

  test "destroy is blocked when agreements exist" do
    theme = TradeBarriers::Theme.find_or_create_by!(name: "Test Theme")
    TradeBarriers::Agreement.create!(title: "Sample agreement", theme: theme)
    assert_not theme.destroy
    assert theme.errors[:base].any? || theme.errors[:agreements].any?
  end
end
