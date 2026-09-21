require "test_helper"

class BroadcastBackfillRequestTest < ActiveSupport::TestCase
  test "validates bounded inclusive ranges" do
    request = BroadcastBackfillRequest.create_for_range!(
      starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 12, 31),
      mode: "discover_only", requested_by: users(:admin)
    )
    assert request.valid?

    too_long = BroadcastBackfillRequest.new(
      scope: "date_range", starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2027, 1, 2),
      mode: "discover_only", requested_by: users(:admin)
    )
    assert_not too_long.valid?
  end

  test "individual queue is complete only after its capture item completes" do
    stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: "#{SecureRandom.uuid}:archive",
      kind: "on_demand", first_seen_at: Time.current, last_seen_at: Time.current)

    request = BroadcastBackfillRequest.queue_stream!(stream:, requested_by: users(:admin))
    assert_equal "running", request.state
    assert request.orchestration_complete?

    request.items.sole.mark_completed!
    assert_equal "completed", request.reload.state
  end
end
