require "test_helper"

# Browser OIDC sign-in with LinkedIn (Users::LinkedinController). The external
# calls (authorize URL build, code exchange, id_token verification) are swapped
# for canned values; we assert the controller establishes a Devise session for
# the verified user.
class LinkedinSignInTest < ActionDispatch::IntegrationTest
  IDENTITY = {
    "sub" => "li-42", "name" => "Nora New", "email" => "nora@example.com", "picture" => "https://x/p.jpg"
  }.freeze

  # Minitest 6 dropped Object#stub and the project has no mocking gem, so swap
  # the class/module methods directly for the duration of the block.
  # stubs: [[receiver, method_name, return_value], ...]
  def stubbing(stubs)
    originals = stubs.map { |recv, name, _| [ recv, name, recv.method(name) ] }
    stubs.each do |recv, name, value|
      recv.singleton_class.send(:define_method, name) { |*, **| value }
    end
    yield
  ensure
    originals.each { |recv, name, meth| recv.singleton_class.send(:define_method, name, meth) }
  end

  test "start redirects the browser to LinkedIn" do
    stubbing([ [ LinkedinOidc, :authorize_url, "https://www.linkedin.com/oauth/v2/authorization?x=1" ] ]) do
      get user_linkedin_authorize_path
    end
    assert_response :redirect
    assert_match "linkedin.com/oauth", response.location
  end

  test "callback creates the user, signs them in, and redirects" do
    # Pin the CSRF state so the callback can present a matching value (scoped to
    # the #start request; the callback runs with real randomness).
    stubbing([ [ LinkedinOidc, :authorize_url, "https://www.linkedin.com/oauth" ],
               [ SecureRandom, :hex, "statetoken" ] ]) do
      get user_linkedin_authorize_path
    end

    stubbing([ [ LinkedinOidc, :exchange_code, { "id_token" => "tok" } ],
               [ LinkedinOidc, :verify_id_token, IDENTITY ] ]) do
      assert_difference -> { User.count }, 1 do
        get user_linkedin_callback_path(state: "statetoken", code: "abc")
      end
    end

    user = User.find_by(provider: "linkedin", uid: "li-42")
    assert_not_nil user
    assert_equal "nora@example.com", user.email
    assert_response :redirect

    # Session established: a login-gated page is now reachable.
    get profile_path
    assert_response :success
  end

  test "callback rejects a mismatched state (CSRF guard)" do
    # No prior #start → no session state → any presented state fails closed.
    get user_linkedin_callback_path(state: "forged", code: "abc")
    assert_redirected_to new_user_session_path
    assert_nil User.find_by(provider: "linkedin", uid: "li-42")
  end

  test "callback surfaces a provider error without creating a user" do
    get user_linkedin_callback_path(error: "access_denied")
    assert_redirected_to new_user_session_path
    assert_equal 0, User.where(provider: "linkedin").count
  end
end
