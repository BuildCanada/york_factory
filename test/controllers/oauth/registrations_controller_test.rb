require "test_helper"

# RFC 7591 dynamic client registration (POST /oauth/register).
class Oauth::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  def register(raw = nil, content_type: "application/json", **fields)
    post "/oauth/register", params: raw || fields.to_json, headers: { "Content-Type" => content_type }
  end

  test "registers a public client and audits it" do
    register(client_name: "Cursor", redirect_uris: [ "cursor://anysphere.cursor-mcp/oauth/callback", "http://localhost:6274/cb" ],
      grant_types: %w[authorization_code refresh_token], application_type: "native", scope: "read:public")
    assert_response :created
    body = response.parsed_body
    assert body["client_id"].present?
    assert_equal "none", body["token_endpoint_auth_method"]
    assert_equal "read:public", body["scope"]
    assert_not body.key?("client_secret")
    assert_equal "no-store", response.headers["Cache-Control"]

    app = Doorkeeper::Application.find_by!(uid: body["client_id"])
    assert app.dynamic?
    assert_not app.confidential?
    assert_equal "127.0.0.1", app.registration_ip.to_s
    event = AuditEvent.find_by!(action: "oauth.client_registered", subject: app)
    assert_equal "client", event.actor_kind
  end

  test "defaults the scope to every public-API scope" do
    register(redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ])
    assert_response :created
    assert_equal "read:public usage:read", response.parsed_body["scope"]
    assert_equal "claude.ai", response.parsed_body["client_name"]
  end

  test "refuses unsafe or missing redirect URIs" do
    [ [], [ "http://evil.example/cb" ], [ "javascript:alert(1)" ], [ "https://ok.example/cb#frag" ], [ "data:text/html,hi" ] ].each do |uris|
      register(client_name: "X", redirect_uris: uris)
      assert_response :bad_request
      assert_equal "invalid_redirect_uri", response.parsed_body["error"], uris.inspect
    end
  end

  test "refuses confidential clients, other grant types and unknown scopes" do
    [ { token_endpoint_auth_method: "client_secret_basic" }, { grant_types: %w[client_credentials] },
      { grant_types: %w[authorization_code implicit] }, { response_types: %w[token] }, { scope: "keys:manage" },
      { application_type: "desktop" } ].each do |extra|
      register(client_name: "X", redirect_uris: [ "https://ok.example/cb" ], **extra)
      assert_response :bad_request
      assert_equal "invalid_client_metadata", response.parsed_body["error"], extra.inspect
    end
  end

  test "refuses a body that isn't JSON" do
    register("redirect_uris=https://ok.example/cb", content_type: "application/x-www-form-urlencoded")
    assert_response :bad_request
    register("{not json")
    assert_response :bad_request
    assert_equal "invalid_client_metadata", response.parsed_body["error"]
  end

  test "rate-limits registration to 10 an hour per IP" do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    10.times do
      register(client_name: "X", redirect_uris: [ "https://ok.example/cb" ])
      assert_response :created
    end
    register(client_name: "X", redirect_uris: [ "https://ok.example/cb" ])
    assert_response :too_many_requests
    assert_equal "slow_down", response.parsed_body["error"]
    assert response.headers["Retry-After"].to_i.positive?
  ensure
    Rack::Attack.cache.store = Rails.cache
  end
end
