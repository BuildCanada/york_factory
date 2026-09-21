require "test_helper"

class Warehouse::Broadcasts::CommandTest < ActiveSupport::TestCase
  test "passes arguments without shell interpolation and caps retained output" do
    marker = "$(touch /tmp/broadcast-command-must-not-exist)"
    result = Warehouse::Broadcasts::Command.new(output_limit: 12).run(
      RbConfig.ruby, "-e", "STDOUT.write(ARGV.fetch(0) * 10)", marker
    )

    assert_equal marker[0, 12], result.stdout
    assert_not File.exist?("/tmp/broadcast-command-must-not-exist")
  end

  test "terminates a command that exceeds its deadline" do
    assert_raises(Warehouse::Broadcasts::Command::TimedOut) do
      Warehouse::Broadcasts::Command.new(timeout: 0.1).run(RbConfig.ruby, "-e", "sleep 5")
    end
  end

  test "raises with bounded diagnostics for failure" do
    error = assert_raises(Warehouse::Broadcasts::Command::Failed) do
      Warehouse::Broadcasts::Command.new.run(RbConfig.ruby, "-e", "warn 'specific failure'; exit 7")
    end
    assert_equal 7, error.result.status.exitstatus
    assert_includes error.message, "specific failure"
  end
end
