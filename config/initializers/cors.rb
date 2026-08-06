Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ORIGINS", "*").split(",")
    resource "/api/v1/*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
    resource "/multi_search", headers: :any, methods: [ :post, :options ]
    resource "/collections/*", headers: :any, methods: [ :get, :options ]
    resource "/canada-spends/*", headers: :any, methods: [ :get, :options ]
  end
end
