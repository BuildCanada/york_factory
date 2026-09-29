require "test_helper"

class Internal::KeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_secret = ENV["EDGE_HMAC_SECRET"]
    ENV["EDGE_HMAC_SECRET"] = "edge-secret"
    @issued = issue_key(scopes: %w[read:public usage:read])
  end

  teardown { ENV["EDGE_HMAC_SECRET"] = @previous_secret }

  test "answers a signed lookup with the key's edge payload" do
    get_signed "/internal/keys/lookup?digest=#{ApiKey::Token.digest(@issued.raw_key)}"

    assert_response :success
    body = response.parsed_body
    assert_equal @issued.api_key.id, body["key_id"]
    assert_equal @issued.api_key.account_id, body["account_id"]
    assert_equal "free", body["plan"]
    assert_equal %w[read:public usage:read], body["scopes"]
    assert_equal "active", body["status"]
    assert_equal({ "rate" => 120, "burst" => 240, "monthly" => 100_000 }, body["limits"])
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "reports revoked keys and unknown digests" do
    Keys::Revoke.call(api_key: @issued.api_key, reason: "user", context: system_context)
    get_signed "/internal/keys/lookup?digest=#{@issued.api_key.token_digest}"
    assert_equal "revoked", response.parsed_body["status"]

    get_signed "/internal/keys/lookup?digest=#{'0' * 64}"
    assert_response :not_found
  end

  test "refuses unsigned or badly signed requests" do
    get "/internal/keys/lookup?digest=#{@issued.api_key.token_digest}"
    assert_response :unauthorized

    headers = Edge::Signature.headers(method: "GET", path: "/internal/keys/lookup?digest=other", secret: "edge-secret")
    get "/internal/keys/lookup?digest=#{@issued.api_key.token_digest}", headers: headers
    assert_response :unauthorized
  end

  private

  def get_signed(path)
    get path, headers: Edge::Signature.headers(method: "GET", path:, secret: "edge-secret")
  end
end
