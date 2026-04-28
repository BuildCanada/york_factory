require "test_helper"

class UserRoleTest < ActiveSupport::TestCase
  test "trade_barriers_editor is in the role enum" do
    assert User.roles.key?("trade_barriers_editor")
  end

  test "can_edit_trade_barriers? is true for editor, admin, superadmin only" do
    editor = User.new(role: "trade_barriers_editor", email: "e@e.com")
    admin  = User.new(role: "admin", email: "a@a.com")
    super_ = User.new(role: "superadmin", email: "s@s.com")
    member = User.new(role: "member", email: "m@m.com")

    assert editor.can_edit_trade_barriers?
    assert admin.can_edit_trade_barriers?
    assert super_.can_edit_trade_barriers?
    assert_not member.can_edit_trade_barriers?
  end
end
