require "test_helper"

class PosthogInitializerTest < ActiveSupport::TestCase
  test "disables PostHog delivery outside production" do
    assert_not Rails.env.production?
    assert_not PostHog.client.enabled?
    assert_not PostHog::Rails.config.logs_enabled
    assert_equal false, PostHog.capture(distinct_id: "local-test", event: "must-not-send")
  end
end
