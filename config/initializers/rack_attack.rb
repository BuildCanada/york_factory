class Rack::Attack
  throttle("subscribers/ip", limit: 5, period: 60) do |req|
    req.ip if req.path == "/api/v1/subscribers" && req.post?
  end

  throttle("auth/google/ip", limit: 10, period: 60) do |req|
    req.ip if req.path == "/api/v1/auth/google" && req.post?
  end

  throttle("admin/login/ip", limit: 5, period: 60) do |req|
    req.ip if req.path == "/admin/login" && req.post?
  end
end
