require "test_helper"

class PublicApiAuthenticationTest < ActionDispatch::IntegrationTest
  class ProbeController < ActionController::API
    include PublicApiAuthentication

    before_action -> { authenticate_public_api!(scopes: [ "read:public" ]) }
    before_action -> { require_api_scope!("usage:read") }, only: :usage

    def show = render(json: { key_id: current_api_caller.api_key&.id, anonymous: current_api_caller.anonymous? })

    def usage = render(json: { ok: true })
  end

  setup { @issued = issue_key(scopes: %w[read:public]) }

  test "a valid key authenticates" do
    with_probe_routes do
      get "/probe", headers: { "Authorization" => "Bearer #{@issued.raw_key}" }
      assert_response :success
      assert_equal @issued.api_key.id, response.parsed_body["key_id"]
    end
  end

  test "no key is an anonymous read:public caller" do
    with_probe_routes do
      get "/probe"
      assert_response :success
      assert response.parsed_body["anonymous"]
    end
  end

  test "a missing scope is a 403 problem with WWW-Authenticate" do
    with_probe_routes do
      get "/probe/usage", headers: { "Authorization" => "Bearer #{@issued.raw_key}" }
      assert_response :forbidden
      assert_equal "application/problem+json", response.media_type
      assert_equal "insufficient_scope", response.parsed_body["code"]
      assert_equal "usage:read", response.parsed_body["required_scope"]
      assert_equal %(Bearer error="insufficient_scope", scope="usage:read"), response.headers["WWW-Authenticate"]
    end
  end

  test "a bad or revoked key is a 401 problem" do
    with_probe_routes do
      get "/probe", headers: { "Authorization" => "Bearer #{@issued.raw_key.chop}x" }
      assert_response :unauthorized
      assert_equal "unauthenticated", response.parsed_body["code"]

      Keys::Revoke.call(api_key: @issued.api_key, reason: "user", context: system_context)
      get "/probe", headers: { "Authorization" => "Bearer #{@issued.raw_key}" }
      assert_response :unauthorized
      assert_equal "API key revoked", response.parsed_body["title"]
    end
  end

  private

  def with_probe_routes(&)
    with_routing do |set|
      set.draw do
        get "/probe", to: "public_api_authentication_test/probe#show"
        get "/probe/usage", to: "public_api_authentication_test/probe#usage"
      end
      yield
    end
  end
end
