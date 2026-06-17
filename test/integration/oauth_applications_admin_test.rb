require "test_helper"

# The Doorkeeper application-management UI requires the full Rails middleware
# stack and the :new/:edit routes that api_only mode strips. These guard against
# regressing back into api_only (which 500s the UI).
class OauthApplicationsAdminTest < ActionDispatch::IntegrationTest
  setup do
    @oauth_app = Doorkeeper::Application.create!(
      name: "ExistingApp",
      redirect_uri: "https://example.com/callback",
      confidential: true
    )
  end

  test "superadmin can list, view, and reach the new/edit forms" do
    sign_in_as users(:superadmin)

    get oauth_applications_path
    assert_response :success
    assert_match "ExistingApp", response.body

    get new_oauth_application_path
    assert_response :success

    get oauth_application_path(@oauth_app)
    assert_response :success

    get edit_oauth_application_path(@oauth_app)
    assert_response :success
  end

  test "superadmin can create an application" do
    sign_in_as users(:superadmin)

    assert_difference -> { Doorkeeper::Application.count }, 1 do
      post oauth_applications_path, params: {
        doorkeeper_application: {
          name: "NewApp",
          redirect_uri: "https://example.com/cb",
          confidential: "1"
        }
      }
    end
    assert_response :redirect
  end

  test "non-superadmin is redirected away from the admin UI" do
    sign_in_as users(:admin)
    get oauth_applications_path
    assert_redirected_to new_user_session_url
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
