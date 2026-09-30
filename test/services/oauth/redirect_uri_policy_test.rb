require "test_helper"

class Oauth::RedirectUriPolicyTest < ActiveSupport::TestCase
  test "https, loopback http and private-use schemes are allowed" do
    [ "https://claude.ai/api/mcp/auth_callback", "http://127.0.0.1:33418/cb", "http://localhost:6274/oauth/callback",
      "http://[::1]:8080/cb", "cursor://anysphere.cursor-mcp/oauth/callback", "com.example.app:/oauth" ].each do |uri|
      assert Oauth::RedirectUriPolicy.valid?(uri), uri
    end
  end

  test "plain http elsewhere, dangerous schemes and fragments are refused" do
    [ "http://example.com/cb", "javascript:alert(1)", "data:text/html,x", "file:///etc/passwd", "https://example.com/cb#x",
      "/relative", "", "https://#{'a' * 2_000}.example/" ].each do |uri|
      assert_not Oauth::RedirectUriPolicy.valid?(uri), uri
    end
  end

  test "matching is exact, except for a loopback IP's port" do
    registered = [ "http://127.0.0.1:33418/cb", "https://app.example/cb" ]
    assert Oauth::RedirectUriPolicy.matches_registered?("https://app.example/cb", registered)
    assert Oauth::RedirectUriPolicy.matches_registered?("http://127.0.0.1:5000/cb", registered)
    assert_not Oauth::RedirectUriPolicy.matches_registered?("https://app.example/cb?x=1", registered)
    assert_not Oauth::RedirectUriPolicy.matches_registered?("https://app.example/cb/", registered)
    assert_not Oauth::RedirectUriPolicy.matches_registered?("http://127.0.0.1:5000/other", registered)
    assert_not Oauth::RedirectUriPolicy.matches_registered?("http://localhost:5000/cb", [ "http://localhost:33418/cb" ])
  end

  test "canonical resources" do
    assert_equal "https://data.buildcanada.com/mcp", Oauth::Settings.canonical_resource("HTTPS://Data.BuildCanada.com:443/mcp/")
    assert_equal "https://data.buildcanada.com", Oauth::Settings.canonical_resource("https://data.buildcanada.com/")
    assert_nil Oauth::Settings.canonical_resource("data.buildcanada.com/mcp")
    assert_nil Oauth::Settings.canonical_resource("https://data.buildcanada.com/mcp#x")
    assert_nil Oauth::Settings.canonical_resource("https://data.buildcanada.com/mcp?x=1")
  end
end
