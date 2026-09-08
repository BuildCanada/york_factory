require "test_helper"

class Api::V1::Metrics::ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    _, @admin_token = ApiKey.issue!(user: users(:admin), name: "metrics-import-admin")
    _, @member_token = ApiKey.issue!(user: users(:member), name: "metrics-import-member")
  end

  test "admin API keys can import X analytics for a supported account" do
    csv = <<~CSV
      Date,Impressions,Likes,Engagements,Bookmarks,Shares,New follows,Unfollows,Replies,Reposts,Profile visits,Create Post,Video views,Media views
      2026-08-11,100,5,8,1,2,3,0,1,2,4,1,20,25
    CSV

    with_upload(csv, "x-analytics.csv", "text/csv") do |file|
      post "/api/v1/metrics/twitter_stats/import",
        params: { account: "build_toronto", file: file },
        headers: auth_headers(@admin_token)
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "twitter", body["platform"]
    assert_equal "build_toronto", body["account"]
    assert_equal 1, body["inserted"]
    assert_equal 100, ::Metrics::TwitterStat.find_by!(account: "build_toronto", date: "2026-08-11").impressions
  end

  test "non-admin API keys cannot upload analytics" do
    post "/api/v1/metrics/twitter_stats/import",
      params: { account: "build_toronto" },
      headers: auth_headers(@member_token)

    assert_response :forbidden
  end

  test "requests without an API key are unauthorized" do
    post "/api/v1/metrics/tiktok_stats/import", params: { account: "build_toronto" }

    assert_response :unauthorized
  end

  test "unsupported accounts are rejected before parsing the file" do
    with_upload("anything", "analytics.csv", "text/csv") do |file|
      post "/api/v1/metrics/twitter_stats/import",
        params: { account: "unknown", file: file },
        headers: auth_headers(@admin_token)
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_upload", JSON.parse(response.body)["error"]
  end

  private

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def with_upload(content, filename, content_type)
    Tempfile.create([ "analytics", File.extname(filename) ]) do |file|
      file.write(content)
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, content_type, original_filename: filename)
      yield upload
    end
  end
end
