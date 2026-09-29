require "test_helper"

class BifrostClientTest < ActiveSupport::TestCase
  setup do
    @bifrost = FakeBifrost.new
    @client = @bifrost.client
  end

  test "creates a virtual key with no LLM providers, using admin basic auth" do
    vk = @client.create_virtual_key(name: "data-api:acct_1:key_2", description: "Build Canada data API key (no LLM access)",
      customer_id: "cust-1", rate_limit: { request_max_limit: 120, request_reset_duration: "1m" })

    request = @bifrost.requests.last
    assert_equal "POST", request[:method]
    assert_equal "https://bifrost.test/api/governance/virtual-keys", request[:url]
    assert_equal "Basic #{Base64.strict_encode64('admin:admin-password')}", request[:headers]["authorization"]
    assert_equal [], request[:json]["provider_configs"]
    assert_equal true, request[:json]["is_active"]
    assert_equal "cust-1", request[:json]["customer_id"]
    assert_equal({ "request_max_limit" => 120, "request_reset_duration" => "1m" }, request[:json]["rate_limit"])
    assert vk.value.start_with?("sk-bf-")
    refute_includes vk.inspect, vk.value
  end

  test "deactivating re-reads the key and sends its budgets and provider configs back" do
    vk = @bifrost.add_virtual_key(name: "data-api:acct_1:key_3",
      provider_configs: [ { "id" => 7, "provider" => "openai", "allowed_models" => [ "*" ], "weight" => 1, "keys" => [ { "key_id" => "k1" } ] } ],
      budgets: [ { "id" => "b1", "max_limit" => 5, "reset_duration" => "1M", "current_usage" => 2 } ])

    assert @client.deactivate_virtual_key(vk["id"])

    assert_equal %w[GET PUT], @bifrost.requests.map { |r| r[:method] }
    put = @bifrost.requests.last[:json]
    assert_equal false, put["is_active"]
    assert_equal [ { "id" => "b1", "max_limit" => 5, "reset_duration" => "1M" } ], put["budgets"]
    assert_equal [ { "id" => 7, "provider" => "openai", "allowed_models" => [ "*" ], "weight" => 1, "key_ids" => [ "k1" ] } ], put["provider_configs"]
    assert_equal false, @bifrost.virtual_keys[vk["id"]]["is_active"]
  end

  test "deactivating a missing key returns false" do
    refute @client.deactivate_virtual_key("vk-missing")
  end

  test "a connection failure or 5xx is Unavailable, with no body in the message" do
    @bifrost.down!
    error = assert_raises(BifrostClient::Unavailable) { @client.list_virtual_keys }
    assert_match(/GET/, error.message)

    http = Class.new do
      def request(*, **) = FakeBifrost::Response.new(status: 503, body: '{"value":"sk-bf-secret"}')
    end.new
    error = assert_raises(BifrostClient::Unavailable) do
      BifrostClient.new(base_url: "https://bifrost.test", username: "u", password: "p", http:).create_virtual_key(name: "x", description: "y")
    end
    refute_includes error.message, "sk-bf-secret"
  end

  test "a 4xx is RequestFailed with its status" do
    http = Class.new do
      def request(*, **) = FakeBifrost::Response.new(status: 401, body: "{}")
    end.new
    error = assert_raises(BifrostClient::RequestFailed) do
      BifrostClient.new(base_url: "https://bifrost.test", username: "u", password: "wrong", http:).list_virtual_keys
    end
    assert_equal 401, error.status
  end

  test "an unconfigured client refuses to call out" do
    assert_raises(BifrostClient::NotConfigured) { BifrostClient.new(base_url: nil, username: nil, password: nil, http: @bifrost).list_virtual_keys }
    assert_empty @bifrost.requests
  end
end
