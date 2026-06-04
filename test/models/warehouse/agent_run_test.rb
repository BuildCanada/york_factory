require "test_helper"

class Warehouse::AgentRunTest < ActiveSupport::TestCase
  test "valid run with required fields" do
    run = Warehouse::AgentRun.new(agent_name: "x", status: "running", started_at: Time.current)
    assert run.valid?
  end

  test "rejects unknown status" do
    run = Warehouse::AgentRun.new(agent_name: "x", status: "weird", started_at: Time.current)
    refute run.valid?
  end

  test "auto-stamps finished_at on terminal transition" do
    run = Warehouse::AgentRun.create!(agent_name: "x", status: "running", started_at: Time.current)
    assert_nil run.finished_at
    run.update!(status: "completed")
    assert_not_nil run.finished_at
  end

  test "does not overwrite finished_at if already set" do
    t = 1.hour.ago
    run = Warehouse::AgentRun.create!(agent_name: "x", status: "completed", started_at: 2.hours.ago, finished_at: t)
    assert_in_delta t, run.finished_at, 1.second
  end

  test "for_agent scope filters" do
    Warehouse::AgentRun.create!(agent_name: "alpha-#{SecureRandom.hex(2)}", status: "running", started_at: Time.current)
    Warehouse::AgentRun.create!(agent_name: "beta-#{SecureRandom.hex(2)}",  status: "running", started_at: Time.current)
    assert_equal 1, Warehouse::AgentRun.for_agent(Warehouse::AgentRun.first.agent_name).count
  end

  test "deleting a run nullifies the agent_run_id on dependent rows" do
    jur = Warehouse::Jurisdiction.find_or_create_by!(code: "AR-#{SecureRandom.hex(2)}") do |j|
      j.name = "AR Test"; j.slug = "ar-#{SecureRandom.hex(2)}"; j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    run = Warehouse::AgentRun.create!(agent_name: "x", status: "running", started_at: Time.current)
    doc = Warehouse::KpiDocument.create!(jurisdiction: jur, fiscal_year: 2099, doc_url: "https://ex.test/#{SecureRandom.hex(4)}", agent_run: run)
    run.destroy!
    assert_nil doc.reload.agent_run_id
  end
end
