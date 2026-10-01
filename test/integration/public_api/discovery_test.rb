require "test_helper"

class PublicApiDiscoveryTest < PublicApiTestCase
  test "the index names the latest revision and links everything" do
    api_get "/v1"
    assert_conforms("getIndex", status: 200)
    assert_equal 31, body.dig("data", "latest_revision")
    assert_equal [ 31, "daily-2026-10-01" ], body["meta"].values_at("revision", "snapshot")
    assert_equal PublicApi::Spec.version, body.dig("data", "version")
    assert_equal "/v1", body.dig("links", "self")
    assert_cache_control "public, max-age=30"
    assert_match(/\Areq_[0-9A-HJKMNP-TV-Z]{26}\z/, body.dig("meta", "request_id"))
    assert_equal body.dig("meta", "request_id"), response.headers["BC-Request-Id"]
  end

  test "/v1/openapi.json is the bundled contract, through the router with a 5 minute cache" do
    api_get "/v1/openapi.json"
    assert_conforms("getOpenapi", status: 200)
    assert_equal PublicApi::Spec.document, body
    assert_cache_control "public, max-age=300"
    assert_equal "getOpenapi", response.headers["BC-Operation"]
    assert_equal "1", response.headers["BC-Usage-Units"]
    assert response.headers["RateLimit"].present?
    refute File.exist?(Rails.root.join("public/v1/openapi.json")), "the static file server would shadow the route"
  end

  test "every contract operation has a route and every action names an operation" do
    ids = PublicApi::V1::BaseController.descendants.flat_map { |c| c.operation_ids.values }
    assert_equal PublicApi::Spec.operations.keys.sort, ids.sort
    PublicApi::Spec.operations.each_value do |op|
      path = "/v1#{op.path.gsub(/\{[^}]+\}/, 'x')}"
      path = "/v1" if op.path == "/"
      route = Rails.application.routes.recognize_path(path, method: :get)
      controller = "#{route[:controller].camelize}Controller".constantize
      assert_equal op.id, controller.operation_ids[route[:action]], "#{op.path} routes to #{route[:controller]}##{route[:action]}"
    end
  end

  test "/v1/me works anonymously" do
    api_get "/v1/me"
    assert_conforms("getMe", status: 200)
    data = body["data"]
    refute data["authenticated"]
    assert_equal "anonymous", data["plan"]
    assert_equal [ "read:public" ], data["scopes"]
    assert_equal 1000, data.dig("limits", "daily_units")
    assert_nil data["account"]
    assert_cache_control "private, no-store"
  end

  test "/v1/me with a key names the account, key, plan, scopes and usage" do
    issued = issue_key(scopes: %w[read:public usage:read])
    api_get "/v1/me", key: issued.raw_key
    assert_conforms("getMe", status: 200)
    data = body["data"]
    assert data["authenticated"]
    assert_equal "free", data["plan"]
    assert_equal "key_#{issued.api_key.id}", data.dig("key", "id")
    assert_equal issued.api_key.token_prefix, data.dig("key", "prefix")
    assert_equal %w[read:public usage:read], data["scopes"]
    assert_equal 1, data.dig("limits", "monthly_units_used"), "this request's own unit"
  end

  test "/v1/me/usage needs a real caller with usage:read" do
    api_get "/v1/me/usage"
    problem = assert_problem("getUsage", 401, "unauthenticated")
    assert_equal "usage:read", problem["required_scope"]
    assert_match(/resource_metadata|scope/, response.headers["WWW-Authenticate"])

    api_get "/v1/me/usage", key: key_with(%w[read:public])
    problem = assert_problem("getUsage", 403, "insufficient_scope")
    assert_equal "usage:read", problem["required_scope"]
    assert_equal %(Bearer error="insufficient_scope", scope="usage:read"), response.headers["WWW-Authenticate"]

    api_get "/v1/me/usage", key: key_with(%w[read:public usage:read]), granularity: "hour"
    assert_conforms("getUsage", status: 200)
    assert_equal [], body["data"]
    assert_nil body.dig("meta", "revision")
    assert_equal [ "coverage_partial" ], body.dig("meta", "caveats").map { |c| c["code"] }
  end

  test "/v1/me/usage checks its range" do
    key = key_with(%w[read:public usage:read])
    api_get "/v1/me/usage", key:, granularity: "minute", from: "2026-09-01T00:00:00Z", to: "2026-09-03T00:00:00Z"
    assert_problem("getUsage", 400, "invalid_parameter")
    api_get "/v1/me/usage", key:, from: "2026-09-03T00:00:00Z", to: "2026-09-01T00:00:00Z"
    assert_problem("getUsage", 400, "invalid_parameter")
  end

  test "a bad key is 401 and a revoked one says so" do
    issued = issue_key(scopes: %w[read:public])
    api_get "/v1/entities", key: "#{issued.raw_key.chop}x"
    assert_problem("listEntities", 401, "unauthenticated")
    refute response.headers.key?("RateLimit"), "a failed authentication is not charged"

    Keys::Revoke.call(api_key: issued.api_key, reason: "user", context: system_context)
    api_get "/v1/entities", key: issued.raw_key
    assert_equal "API key revoked", assert_problem("listEntities", 401, "unauthenticated")["title"]
  end

  test "a suspended account's key is 403 account_suspended" do
    issued = issue_key(scopes: %w[read:public])
    issued.api_key.account.update!(suspended_at: Time.current, suspended_reason: "test")
    api_get "/v1/entities", key: issued.raw_key
    assert_problem("listEntities", 403, "account_suspended")
  end

  test "anonymous access can be turned off" do
    with_env("PUBLIC_API_ANONYMOUS" => "false") do
      api_get "/v1/entities"
      assert_problem("listEntities", 401, "unauthenticated")
    end
  end

  test "unknown paths and other methods under /v1 are 404 problems" do
    get "/v1/nothing/here"
    assert_response :not_found
    assert_equal "not_found", body["code"]
    assert_equal "application/problem+json", response.media_type
    post "/v1/entities"
    assert_response :not_found
    assert_equal "not_found", body["code"]
  end

  test "an unexpected failure is a 500 internal_error problem" do
    FactFactory::RevisionQuery.stub(:served, -> { raise ActiveRecord::StatementInvalid, "boom" }) do
      api_get "/v1/entities"
    end
    problem = assert_problem("listEntities", 500, "internal_error")
    assert_includes problem["detail"], problem["instance"]
    assert_equal "0", response.headers["BC-Usage-Units"]
  end

  test "no served revision yet is 503 revision_building with Retry-After" do
    empty = FactFactory::RevisionQuery::Served.new(latest: nil, committed: {}, pruned: Set[], snapshots: {}, purged_through: nil)
    FactFactory::RevisionQuery.stub(:served, empty) do
      api_get "/v1/entities"
    end
    problem = assert_problem("listEntities", 503, "revision_building")
    assert_equal "30", response.headers["Retry-After"]
    assert_equal 30, problem["retry_after_seconds"]
  end

  test "the host constraint keeps /v1 on data.buildcanada.com in production" do
    with_env("PUBLIC_API_HOSTS" => "data.buildcanada.com") do
      host! "api.buildcanada.com"
      get "/v1"
      assert_response :not_found
      refute_equal "application/json", response.media_type
      host! "data.buildcanada.com"
      get "/v1"
      assert_conforms("getIndex", status: 200)
    end
  end
end
