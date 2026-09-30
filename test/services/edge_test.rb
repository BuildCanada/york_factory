require "test_helper"

class EdgeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class RecordingHttp
    attr_reader :requests
    attr_accessor :status

    def initialize(status: 200)
      @requests = []
      @status = status
    end

    def request(method, url, headers:, body:)
      @requests << { method:, url:, headers:, body: }
      FakeBifrost::Response.new(status: @status, body: "")
    end
  end

  test "signatures verify within the window and fail outside it or when altered" do
    headers = Edge::Signature.headers(method: "GET", path: "/internal/keys/lookup?digest=ab", secret: "s")
    args = { method: "GET", path: "/internal/keys/lookup?digest=ab", body: "", timestamp: headers["BC-Edge-Timestamp"], signature: headers["BC-Edge-Signature"], secret: "s" }

    assert Edge::Signature.valid?(**args)
    refute Edge::Signature.valid?(**args, path: "/internal/keys/lookup?digest=cd")
    refute Edge::Signature.valid?(**args, secret: "other")
    refute Edge::Signature.valid?(**args, now: 2.minutes.from_now)
  end

  test "pushes a live key as a signed PUT of its lookup payload and a revoked key as DELETE" do
    api_key = issue_key.api_key
    http = RecordingHttp.new
    push = Edge::Push.new(http:, url: "https://edge.test", secret: "edge-secret")

    push.key(api_key)
    put = http.requests.last
    assert_equal "PUT", put[:method]
    assert_equal "https://edge.test/internal/keys/#{api_key.token_digest}", put[:url]
    assert_equal api_key.lookup_payload.as_json, JSON.parse(put[:body])
    assert Edge::Signature.valid?(method: "PUT", path: "/internal/keys/#{api_key.token_digest}", body: put[:body],
      timestamp: put[:headers]["BC-Edge-Timestamp"], signature: put[:headers]["BC-Edge-Signature"], secret: "edge-secret")

    api_key.update!(revoked_at: Time.current)
    push.key(api_key)
    assert_equal "DELETE", http.requests.last[:method]
  end

  test "a failed push is retried in the background" do
    api_key = issue_key.api_key
    push = Edge::Push.new(http: RecordingHttp.new(status: 503), url: "https://edge.test", secret: "edge-secret")

    assert_enqueued_with(job: ApiKey::PushToEdgeJob) { refute push.key(api_key) }
  end

  test "pushes nothing when the edge isn't configured" do
    http = RecordingHttp.new
    refute Edge::Push.new(http:, url: nil, secret: nil).key(issue_key.api_key)
    assert_empty http.requests
  end
end
