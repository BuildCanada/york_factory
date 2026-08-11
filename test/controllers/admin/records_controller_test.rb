require "test_helper"

class Admin::RecordsControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  setup do
    @source = Warehouse::Source.create!(
      name: "record_browser_#{SecureRandom.hex(4)}",
      url: "https://example.com/data.csv",
      format: "csv"
    )
    @ingestion = @source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/record-browser.csv",
      checksum: SecureRandom.hex(32),
      status: "complete"
    )
    @ingestion.lineage_entries.create!(
      transformation_type: "deterministic",
      source_field: "vendor",
      source_value: "Acme Corp"
    )
  end

  test "redirects unauthenticated users" do
    get admin_records_path

    assert_redirected_to new_user_session_path
  end

  test "lists recent ingestions" do
    sign_in_admin

    get admin_records_path

    assert_response :success
    assert_select "h1", "Record Browser"
    assert_select "a[href='#{admin_records_path(raw_ingestion_id: @ingestion.id)}']", text: "Browse"
  end

  test "browses postgres records linked to an ingestion" do
    sign_in_admin

    get admin_records_path(raw_ingestion_id: @ingestion.id, dataset: "lineage_entries")

    assert_response :success
    assert_select "h2", "Lineage entries"
    assert_select "th", "source_value"
    assert_select "td", text: "Acme Corp"
    assert_select "a", text: "Lineage entries"
  end

  test "rejects datasets without a raw ingestion foreign key" do
    sign_in_admin

    get admin_records_path(raw_ingestion_id: @ingestion.id, dataset: "users")

    assert_response :not_found
  end
end
