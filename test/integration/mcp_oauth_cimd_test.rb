require "test_helper"

# Client ID Metadata Documents, the MCP 2026-07-28 preferred registration:
# an https client_id is fetched (through Oauth::SafeFetch, stubbed here),
# validated and upserted as a public client.
class McpOauthCimdTest < ActionDispatch::IntegrationTest
  CLIENT_ID = "https://app.example.com/oauth/client-metadata.json".freeze

  setup do
    @member = users(:member)
    @fetches = 0
  end

  def document(**overrides)
    { client_id: CLIENT_ID, client_name: "Example MCP Client", client_uri: "https://app.example.com",
      logo_uri: "https://app.example.com/logo.png", redirect_uris: [ REDIRECT_URI ],
      grant_types: %w[authorization_code refresh_token], response_types: %w[code], token_endpoint_auth_method: "none" }.merge(overrides)
  end

  def serving(body, status: 200, cache_control: "max-age=3600", &)
    fetch = lambda do |url, **|
      @fetches += 1
      assert_equal CLIENT_ID, url
      Oauth::SafeFetch::Response.new(status:, headers: { "cache-control" => cache_control }, body: body.is_a?(String) ? body : body.to_json)
    end
    Oauth::SafeFetch.stub(:get, fetch, &)
  end

  test "a metadata-document client authorizes and gets a token bound to the resource" do
    sign_in_user(@member)
    pkce = pkce_pair
    serving(document) do
      get "/oauth/authorize", params: authorize_params(client_id: CLIENT_ID, pkce:)
      assert_response :success
      assert_match "Example MCP Client", response.body
      assert_match "app.example.com", response.body
      assert_match "metadata document at", response.body

      query = authorize!(client_id: CLIENT_ID, pkce:)
      tokens = exchange_code!(client_id: CLIENT_ID, code: query["code"], pkce:)
      assert_response :success
      assert_equal MCP_RESOURCE, Doorkeeper::AccessToken.by_token(tokens["access_token"]).resource

      mcp_call(tokens["access_token"])
      assert_response :success
    end

    app = Doorkeeper::Application.find_by!(uid: CLIENT_ID)
    assert app.metadata_document?
    assert_equal CLIENT_ID, app.metadata_url
    assert_equal "https://app.example.com/logo.png", app.logo_url
    assert_equal 1, @fetches, "the document is cached between requests"
    assert AuditEvent.exists?(action: "oauth.client_registered", subject: app)
  end

  test "the cached document is refetched once it expires" do
    sign_in_user(@member)
    serving(document, cache_control: "max-age=60") do
      get "/oauth/authorize", params: authorize_params(client_id: CLIENT_ID, pkce: pkce_pair)
      travel 6.minutes do
        get "/oauth/authorize", params: authorize_params(client_id: CLIENT_ID, pkce: pkce_pair)
      end
    end
    assert_equal 2, @fetches
  end

  test "a document whose client_id doesn't match its URL is refused" do
    sign_in_user(@member)
    serving(document(client_id: "https://other.example/client.json")) do
      get "/oauth/authorize", params: authorize_params(client_id: CLIENT_ID, pkce: pkce_pair)
    end
    assert_response :bad_request
    assert_match "different client_id", response.body
    assert_not Doorkeeper::Application.exists?(uid: CLIENT_ID)
  end

  test "invalid documents are refused" do
    sign_in_user(@member)
    [ document(redirect_uris: [ "http://evil.example/cb" ]), document(client_name: nil), document(token_endpoint_auth_method: "private_key_jwt"),
      document(client_secret: "shh"), document(grant_types: %w[client_credentials]), "not json", [ 1, 2 ] ].each do |body|
      Rails.cache.clear
      serving(body) { get "/oauth/authorize", params: authorize_params(client_id: CLIENT_ID, pkce: pkce_pair) }
      assert_response :bad_request, body.inspect
    end
    serving(document, status: 404) { get "/oauth/authorize", params: authorize_params(client_id: CLIENT_ID, pkce: pkce_pair) }
    assert_response :bad_request
    assert_not Doorkeeper::Application.exists?(uid: CLIENT_ID)
  end

  test "a redirect URI not in the document is refused" do
    sign_in_user(@member)
    serving(document) do
      get "/oauth/authorize", params: authorize_params(client_id: CLIENT_ID, pkce: pkce_pair, redirect_uri: "https://attacker.example/cb")
    end
    assert_response :bad_request
    assert_nil response.location
  end

  test "an unreachable document keeps a known client working from the stored copy" do
    sign_in_user(@member)
    serving(document, cache_control: "max-age=300") { get "/oauth/authorize", params: authorize_params(client_id: CLIENT_ID, pkce: pkce_pair) }
    failing = ->(*, **) { raise Oauth::SafeFetch::Error, "couldn't be fetched (Timeout)" }
    travel 1.hour do
      Oauth::SafeFetch.stub(:get, failing) do
        get "/oauth/authorize", params: authorize_params(client_id: CLIENT_ID, pkce: pkce_pair)
      end
      assert_response :success
    end
  end

  test "metadata-document client IDs must be https URLs with a path" do
    assert Oauth::ClientMetadataDocument.url?(CLIENT_ID)
    assert_not Oauth::ClientMetadataDocument.url?("http://app.example.com/client.json")
    assert_not Oauth::ClientMetadataDocument.url?("https://app.example.com")
    assert_not Oauth::ClientMetadataDocument.url?("https://app.example.com/")
    assert_not Oauth::ClientMetadataDocument.url?("https://user@app.example.com/client.json")
    assert_not Oauth::ClientMetadataDocument.url?("https://app.example.com/a/../client.json")
    assert_not Oauth::ClientMetadataDocument.url?("abc123")
  end
end
