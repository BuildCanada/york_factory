require "test_helper"

class LumaEventGuestTest < ActiveSupport::TestCase
  def setup
    @luma_event = LumaEvent.create!(
      luma_event_id: "test-event-123",
      name: "Test Event",
      start_at: 1.day.from_now
    )

    @guest = LumaEventGuest.create!(
      luma_event: @luma_event,
      luma_user_id: "user-123",
      name: "John Doe",
      email: "john@example.com",
      approval_status: "approved"
    )
  end

  test "should create guest with required fields" do
    guest = LumaEventGuest.new(
      luma_event: @luma_event,
      luma_user_id: "user-456",
      name: "Jane Smith",
      email: "jane@example.com"
    )
    assert guest.save
  end

  test "should require luma_user_id" do
    guest = LumaEventGuest.new(
      luma_event: @luma_event,
      name: "Test",
      email: "test@example.com"
    )
    assert_not guest.save
    assert_includes guest.errors.full_messages, "Luma user can't be blank"
  end

  test "should require unique luma_user_id per event" do
    duplicate = LumaEventGuest.new(
      luma_event: @luma_event,
      luma_user_id: @guest.luma_user_id,
      name: "Duplicate",
      email: "duplicate@example.com"
    )
    assert_not duplicate.save
    assert_includes duplicate.errors.full_messages, "Luma user has already been taken"
  end

  test "should validate email format" do
    guest = LumaEventGuest.new(
      luma_event: @luma_event,
      luma_user_id: "user-789",
      name: "Invalid Email",
      email: "invalid-email"
    )
    assert_not guest.save
    assert_includes guest.errors.full_messages, "Email is invalid"
  end

  test "checked_in scope should return checked in guests" do
    @guest.update!(checked_in: true)

    checked_in_guests = LumaEventGuest.checked_in
    assert_includes checked_in_guests, @guest
  end

  test "should detect recently checked in guests" do
    @guest.update!(checked_in: true, checked_in_at: 30.minutes.ago)
    assert @guest.recently_checked_in?

    @guest.update!(checked_in_at: 2.hours.ago)
    assert_not @guest.recently_checked_in?
  end
end
