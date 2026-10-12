require "test_helper"

class ActiveStorageDirectUploadsTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  DIRECT_UPLOAD_PARAMS = {
    blob: {
      filename: "test.png",
      byte_size: 8,
      checksum: Digest::MD5.base64digest("12345678"),
      content_type: "image/png"
    }
  }.freeze

  test "direct upload is rejected without a session" do
    assert_no_difference "ActiveStorage::Blob.count" do
      post rails_direct_uploads_path, params: DIRECT_UPLOAD_PARAMS, as: :json
    end
    assert_response :unauthorized
  end

  test "direct upload is rejected for a non-admin member" do
    post user_session_path, params: { email: users(:member).email, password: "password123" }

    assert_no_difference "ActiveStorage::Blob.count" do
      post rails_direct_uploads_path, params: DIRECT_UPLOAD_PARAMS, as: :json
    end
    assert_response :unauthorized
  end

  test "direct upload works for a signed-in admin" do
    sign_in_admin

    assert_difference "ActiveStorage::Blob.count", 1 do
      post rails_direct_uploads_path, params: DIRECT_UPLOAD_PARAMS, as: :json
    end
    assert_response :success
    assert JSON.parse(response.body)["direct_upload"].present?
  end
end
