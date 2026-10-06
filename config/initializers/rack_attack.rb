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

  # OAuth abuse controls (docs/public-interface-design.md §8.2). Dynamic
  # client registration: 10 an hour per IP, and 200 an hour in all.
  throttle("oauth/register/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.path == "/oauth/register" && req.post?
  end

  throttle("oauth/register/global", limit: 200, period: 1.hour) do |req|
    "all" if req.path == "/oauth/register" && req.post?
  end

  # Authorization requests that name a Client ID Metadata Document can make
  # us fetch a URL: 30 an hour per IP. (Each document is also cached, and a
  # failed fetch isn't retried for a minute.)
  throttle("oauth/cimd/ip", limit: 30, period: 1.hour) do |req|
    req.ip if req.path == "/oauth/authorize" && req.params["client_id"].to_s.start_with?("https://")
  end

  # The token endpoint: 60 a minute per IP.
  throttle("oauth/token/ip", limit: 60, period: 60) do |req|
    req.ip if req.post? && (req.path == "/oauth/token" || req.path == "/oauth/revoke")
  end

  # OAuth endpoints answer throttling in OAuth's JSON error shape.
  self.throttled_responder = lambda do |request|
    match = request.env["rack.attack.match_data"] || {}
    retry_after = (match[:period] || 60).to_i - (Time.now.to_i % (match[:period] || 60).to_i)
    headers = { "Retry-After" => retry_after.to_s }
    if request.path.start_with?("/oauth/")
      [ 429, headers.merge("Content-Type" => "application/json"),
        [ { error: "slow_down", error_description: "Too many requests. Try again in #{retry_after} seconds." }.to_json ] ]
    else
      [ 429, headers.merge("Content-Type" => "text/plain"), [ "Retry later\n" ] ]
    end
  end
end
