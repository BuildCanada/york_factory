require "test_helper"

class Keys::MassRotateJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "puts every live Bifrost key on a 7-day grace, audits it and emails the owners" do
    bifrost = FakeBifrost.new
    bifrost_key = issue_key(issuer: bifrost.issuer).api_key
    local_key = issue_key.api_key

    count = nil
    assert_enqueued_emails 1 do
      count = Keys::MassRotateJob.perform_now(reason: "Bifrost breach drill", actor_id: users(:superadmin).id)
    end

    assert_equal 1, count
    assert_equal "rotating", bifrost_key.reload.status
    assert_in_delta 7.days.from_now, bifrost_key.grace_until, 5.seconds
    assert_nil local_key.reload.grace_until
    assert AuditEvent.exists?(action: "key.mass_rotation", subject_id: bifrost_key.id)
    assert_equal "Bifrost breach drill", AuditEvent.find_by!(action: "admin.mass_rotation").metadata["reason"]

    # The owner can then rotate with one click; the old key keeps its deadline.
    result = Keys::Rotate.call(api_key: bifrost_key, user: bifrost_key.user, grace: "7d", issuer: bifrost.issuer, context: system_context)
    assert result.ok?
    assert_in_delta 7.days.from_now, bifrost_key.reload.grace_until, 5.seconds
  end
end
