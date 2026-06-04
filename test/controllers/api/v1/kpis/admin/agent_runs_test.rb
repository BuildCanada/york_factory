require "test_helper"

class Api::V1::Kpis::Admin::AgentRunsTest < ActionDispatch::IntegrationTest
  setup do
    @token = Warehouse::ApiToken.issue!(name: "ar-test-#{SecureRandom.hex(2)}", scopes: [ "kpis:write" ])
    @auth = { "Authorization" => "Bearer #{@token}" }
  end

  test "POST creates a run in status=running with triggered_by=token name" do
    post "/api/v1/kpis/admin/agent_runs",
      params: { agent_run: { agent_name: "test-agent", agent_version: "v1", input_params: { a: 1 } } },
      headers: @auth, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "running", body["status"]
    assert_match(/\Aar-test-/, body["triggered_by"])
    assert_equal({ "a" => 1 }, body["input_params"])
  end

  test "PATCH closes the run and stamps finished_at" do
    post "/api/v1/kpis/admin/agent_runs",
      params: { agent_run: { agent_name: "test-agent" } }, headers: @auth, as: :json
    run_id = JSON.parse(response.body)["id"]

    patch "/api/v1/kpis/admin/agent_runs/#{run_id}",
      params: { agent_run: { status: "completed", report: "# done", summary: { inserted: 42 } } },
      headers: @auth, as: :json
    assert_response :success

    run = Warehouse::AgentRun.find(run_id)
    assert_equal "completed", run.status
    assert_equal({ "inserted" => 42 }, run.summary)
    assert_not_nil run.finished_at
  end

  test "GET returns full row including report" do
    run = Warehouse::AgentRun.create!(agent_name: "t", status: "completed", started_at: Time.current, report: "# x")
    get "/api/v1/kpis/admin/agent_runs/#{run.id}", headers: @auth
    assert_response :success
    assert_equal "# x", JSON.parse(response.body)["report"]
  end

  test "rejects unauthenticated requests" do
    post "/api/v1/kpis/admin/agent_runs", params: { agent_run: { agent_name: "x" } }
    assert_response :unauthorized
  end
end
