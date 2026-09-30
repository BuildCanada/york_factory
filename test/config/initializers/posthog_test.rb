require "test_helper"

class PosthogInitializerTest < ActiveSupport::TestCase
  test "disables PostHog delivery outside production" do
    assert_not Rails.env.production?
    assert_not PostHog.client.enabled?
    assert_not PostHog::Rails.config.logs_enabled
    assert_equal false, PostHog.capture(distinct_id: "local-test", event: "must-not-send")
  end

  test "keeps exception capture on for server and job processes" do
    assert_not InteractiveProcess.detected?
    assert PostHog::Rails.config.auto_capture_exceptions
    assert PostHog::Rails.config.report_rescued_exceptions
  end

  test "treats a runner process as interactive" do
    skip "RunnerCommand already loaded" if defined?(Rails::Command::RunnerCommand)
    Rails::Command.const_set(:RunnerCommand, Class.new)
    assert InteractiveProcess.detected?
    Rails::Command.send(:remove_const, :RunnerCommand)
  end
end
