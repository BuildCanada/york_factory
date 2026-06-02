require "test_helper"

class Admin::Kpis::AdminKpisTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    @jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(code: "AK-#{SecureRandom.hex(2)}") do |j|
      j.name = "Admin KPI Test"; j.slug = "ak-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jurisdiction, slug: "admin-test-org-#{SecureRandom.hex(2)}", canonical_name: "Admin Test Org #{SecureRandom.hex(2)}")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jurisdiction, organization: @org,
      fiscal_year: 2024, doc_url: "https://example.com/admin-test-#{SecureRandom.hex(4)}.pdf",
      doc_title: "Admin Test Doc")
    @run = Warehouse::AgentRun.create!(agent_name: "admin-test-run", status: "completed",
      started_at: 1.hour.ago, finished_at: 30.minutes.ago,
      summary: { citations_inserted: 1 }, report: "# Test report\n\nHello.")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "admin-m-#{SecureRandom.hex(2)}",
      canonical_name: "Admin Test Measure", unit: @unit, agent_run: @run)
    @citation = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 42, agent_run: @run)
  end

  test "redirects unauthenticated users from agent_runs" do
    get admin_kpis_agent_runs_url
    assert_redirected_to new_user_session_path
  end

  test "admin renders agent_runs index" do
    sign_in_admin
    get admin_kpis_agent_runs_url
    assert_response :success
    assert_match "Agent Runs", @response.body
    assert_match "admin-test-run", @response.body
  end

  test "admin renders agent_runs show with rendered markdown report" do
    sign_in_admin
    get admin_kpis_agent_run_url(@run)
    assert_response :success
    assert_match "Agent Run ##{@run.id}", @response.body
    assert_match "<h1>Test report</h1>", @response.body
  end

  test "admin renders measures index with filter" do
    sign_in_admin
    get admin_kpis_measures_url(jurisdiction: @jurisdiction.slug)
    assert_response :success
    assert_match @measure.canonical_name, @response.body
  end

  test "admin renders measure show with facts table" do
    sign_in_admin
    get admin_kpis_measure_url(@measure)
    assert_response :success
    assert_match @measure.canonical_name, @response.body
    assert_match "Resolved facts", @response.body
  end

  test "admin renders citations index" do
    sign_in_admin
    get admin_kpis_citations_url
    assert_response :success
    assert_match @measure.canonical_name, @response.body
  end

  test "admin renders citation show with agent_run + document context" do
    sign_in_admin
    get admin_kpis_citation_url(@citation)
    assert_response :success
    assert_match "Citation ##{@citation.id}", @response.body
    assert_match @run.agent_name, @response.body
    assert_match @doc.doc_url, @response.body
  end
end
