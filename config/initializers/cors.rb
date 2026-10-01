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
      expose: %w[ETag BC-Revision BC-Request-Id BC-Usage-Units BC-Operation BC-Quota-Remaining RateLimit RateLimit-Policy Retry-After Location],
      max_age: 86_400
  end
end
