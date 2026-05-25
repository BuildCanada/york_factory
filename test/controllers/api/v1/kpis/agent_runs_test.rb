require "test_helper"

class Api::V1::Kpis::AgentRunsTest < ActionDispatch::IntegrationTest
  setup do
    @r1 = Warehouse::AgentRun.create!(agent_name: "alpha-#{SecureRandom.hex(2)}", status: "completed", started_at: 1.hour.ago, finished_at: 50.minutes.ago, report: "# r1")
    @r2 = Warehouse::AgentRun.create!(agent_name: "alpha-#{SecureRandom.hex(2)}", status: "running",   started_at: 10.minutes.ago)
  end

  test "index lists runs without the report body" do
    get "/api/v1/kpis/agent_runs"
    assert_response :success
    rows = JSON.parse(response.body)["data"]
    assert(rows.any? { |r| r["id"] == @r1.id })
    refute rows.first.key?("report")
  end

  test "index filters by agent name" do
    get "/api/v1/kpis/agent_runs", params: { agent: @r1.agent_name }
    rows = JSON.parse(response.body)["data"]
    assert_equal [ @r1.id ], rows.map { |r| r["id"] }
  end

  test "show includes the report body" do
    get "/api/v1/kpis/agent_runs/#{@r1.id}"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "# r1", body["report"]
  end
end
