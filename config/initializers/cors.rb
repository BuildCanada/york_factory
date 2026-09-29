Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ORIGINS", "*").split(",")
    resource "/api/v1/*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end

  # The public data API is read-only public data: any origin may read it
  # (a key's own allowed_origins still apply, in Keys::Verify).
  allow do
    origins "*"
    resource "/v1/*",
      headers: %w[Authorization Accept-Language If-None-Match],
      methods: [ :get, :head, :options ],
      expose: %w[ETag BC-Release BC-Request-Id BC-Usage-Units BC-Operation BC-Quota-Remaining RateLimit RateLimit-Policy Retry-After Location],
      max_age: 86_400
  end

  # Browser-based MCP clients (MCP Inspector, web IDEs) discover and use the
  # OAuth endpoints and /mcp from their own origin. None of these use
  # cookies, so any origin may call them.
  allow do
    origins "*"
    resource "/.well-known/*", headers: :any, methods: [ :get, :options, :head ]
    resource "/oauth/token", headers: :any, methods: [ :post, :options ]
    resource "/oauth/revoke", headers: :any, methods: [ :post, :options ]
    resource "/oauth/register", headers: :any, methods: [ :post, :options ]
    resource "/mcp", headers: :any, methods: [ :post, :options ],
      expose: %w[WWW-Authenticate Mcp-Protocol-Version]
  end
end
