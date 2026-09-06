require "test_helper"

class Api::V1::PollPublicationsTest < ActionDispatch::IntegrationTest
  setup do
    _, @key = ApiKey.issue!(user: users(:admin), name: "poll-test")
    @poll = Memo.create!(slug: "test-poll-publication", title_en: "Poll", content_kind: "poll", survey_slug: "survey",
      body_en: "## Analysis", published_at: 1.day.ago, news_release_en: "Public news", subscriber_email_en: "Private email", tweet_en: "Private tweet")
    @poll.crosstabs_json.attach(io: StringIO.new('{"schemaVersion":2}'), filename: "crosstabs.json", content_type: "application/json", identify: false)
  end

  test "public poll includes downloads and news but not launch copy" do
    get api_v1_memo_url(@poll.slug)
    assert_response :success
    payload = response.parsed_body
    assert_equal "poll", payload["content_kind"]
    assert_includes payload.dig("poll", "news_release"), "Public news"
    assert payload.dig("poll", "downloads", "crosstabs_json")
    assert_not payload["poll"].key?("launch_copy")
    assert_not_includes response.body, "Private email"
  end

  test "French markdown downloads preserve chart source and locale" do
    markdown = "## Résultats\n\n```buildcanada-chart\n{\"data\":54}\n```"
    @poll.update!(body_fr: markdown)
    get api_v1_memo_url(@poll.slug), params: { locale: "fr" }
    url = response.parsed_body.dig("poll", "downloads", "analysis_markdown")
    assert_includes url, "locale=fr"
    get url
    assert_response :success
    assert_equal markdown, response.body
  end

  test "poll index filters existing memos and hides drafts" do
    get api_v1_memos_url, params: { content_kind: "poll" }
    assert_equal [ @poll.slug ], response.parsed_body["data"].map { |item| item["slug"] }
    @poll.update!(published_at: nil)
    get api_v1_memos_url, params: { content_kind: "poll" }
    assert_empty response.parsed_body["data"]
  end

  test "downloads become unavailable when the poll is unpublished" do
    url = download_api_v1_memo_url(@poll.slug, asset: "crosstabs_json")
    get url
    assert_response :success
    assert_equal 2, response.parsed_body["schemaVersion"]
    @poll.update!(published_at: nil)
    get url
    assert_response :not_found
    get url, headers: { "Authorization" => "Bearer #{@key}" }
    assert_response :success
  end

  test "only named report attachments are downloadable" do
    get download_api_v1_memo_url(@poll.slug, asset: "seo_image")
    assert_response :not_found
  end

  test "admin preview includes launch copy and API keys cannot publish polls" do
    get api_v1_memo_url(@poll.slug), headers: { "Authorization" => "Bearer #{@key}" }
    assert_equal "Private email", response.parsed_body.dig("poll", "launch_copy", "subscriber_email_markdown")
    post api_v1_memos_url, params: { memo: { slug: "new-poll", title_en: "New poll", content_kind: "poll", survey_slug: "survey", published_at: 1.day.ago.iso8601 } },
      headers: { "Authorization" => "Bearer #{@key}" }, as: :json
    assert_response :created
    assert_nil Memo.find_by!(slug: "new-poll").published_at
  end
end
