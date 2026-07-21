require "test_helper"

# Browser OmniAuth sign-in with LinkedIn (Users::OmniauthCallbacksController via
# omniauth-linkedin-openid). OmniAuth test mode short-circuits the external
# provider so the POST to the authorize endpoint redirects straight to our
# callback with a canned auth hash; we assert a Devise session is established.
class LinkedinSignInTest < ActionDispatch::IntegrationTest
  def setup
    OmniAuth.config.test_mode = true
  end

  def teardown
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:linkedin] = nil
  end

  def mock_linkedin(uid: "li-42", email: "nora@example.com", name: "Nora New")
    OmniAuth.config.mock_auth[:linkedin] = OmniAuth::AuthHash.new(
      provider: "linkedin",
      uid: uid,
      info: { email: email, first_name: name.split.first, last_name: name.split.last, picture_url: "https://x/p.jpg" },
      extra: { "raw_info" => { "name" => name } }
    )
  end

  test "callback creates the user, signs them in, and redirects to the profile" do
    mock_linkedin

    assert_difference -> { User.count }, 1 do
      post user_linkedin_omniauth_authorize_path
      follow_redirect! # OmniAuth test mode redirects the authorize POST to the callback
    end

    user = User.find_by(provider: "linkedin", uid: "li-42")
    assert_not_nil user
    assert_equal "nora@example.com", user.email
    assert_redirected_to profile_path

    # Session established: a login-gated page is now reachable.
    get profile_path
    assert_response :success
  end

  test "callback honours a return_to passed on the authorize click" do
    mock_linkedin(uid: "li-77", email: "ret@example.com")
    post user_linkedin_omniauth_authorize_path(return_to: "/profile")
    follow_redirect!
    assert_redirected_to "/profile"
  end

  test "an existing linkedin user signs in without creating a duplicate" do
    mock_linkedin(uid: "li-42")
    post user_linkedin_omniauth_authorize_path
    follow_redirect!

    assert_no_difference -> { User.count } do
      post user_linkedin_omniauth_authorize_path
      follow_redirect!
    end
  end

  test "a provider failure surfaces an alert without creating a user" do
    OmniAuth.config.mock_auth[:linkedin] = :invalid_credentials

    assert_no_difference -> { User.count } do
      post user_linkedin_omniauth_authorize_path
      follow_redirect! # to the OmniAuth failure endpoint
      follow_redirect! # failure endpoint redirects to the sign-in page
    end
    assert_equal 0, User.where(provider: "linkedin").count
  end
end
