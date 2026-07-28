require "test_helper"

class Admin::UploadsControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  test "unauthenticated upload redirects to login" do
    assert_no_difference "ActiveStorage::Blob.count" do
      post admin_uploads_path, params: { file: fixture_file_upload("test-image.jpg", "image/jpeg") }
    end
    assert_redirected_to new_user_session_path
  end

  test "create stores the file as a blob and returns an absolute url" do
    sign_in_admin

    assert_difference "ActiveStorage::Blob.count", 1 do
      post admin_uploads_path, params: { file: fixture_file_upload("test-image.jpg", "image/jpeg") }
    end

    assert_response :created
    body = JSON.parse(response.body)
    blob = ActiveStorage::Blob.find_signed(body["signed_id"])

    assert_equal "test-image.jpg", body["filename"]
    assert_equal "image/jpeg", body["content_type"]
    assert_match %r{\Ahttp.*/rails/active_storage/blobs/redirect/#{Regexp.escape(body["signed_id"])}/}, body["url"]
    assert_equal "test-image.jpg", blob.filename.to_s
  end

  test "create without a file returns unprocessable entity" do
    sign_in_admin

    post admin_uploads_path
    assert_response :unprocessable_entity
    assert_equal "file is required", JSON.parse(response.body)["error"]
  end
end
