require "test_helper"

class Admin::PollPublicationsTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  test "poll editor renders report uploads and launch copy" do
    sign_in_admin
    get new_admin_memo_path
    assert_response :success
    assert_select "select[name='memo[content_kind]']"
    assert_select "input[name='memo[analysis_pdf_en]']"
    assert_select "textarea[name='memo[subscriber_email_en]']"
    assert_select "textarea[name='memo[tweet_en]']"
    get admin_memos_path
    assert_response :success
    assert_select "form[action='#{import_poll_admin_memos_path}']"
  end

  test "only an authenticated admin can import and malformed JSON is rejected" do
    post import_poll_admin_memos_path
    assert_redirected_to new_user_session_path
    sign_in_admin
    Tempfile.create([ "publication", ".json" ]) do |file|
      file.write("not JSON")
      file.flush
      assert_no_difference "Memo.count" do
        post import_poll_admin_memos_path, params: { publication_export: Rack::Test::UploadedFile.new(file.path, "application/json") }
      end
      assert_redirected_to admin_memos_path
      assert_match "Import failed", flash[:alert]
    end
  end
end
