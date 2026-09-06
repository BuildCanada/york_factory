require "test_helper"

class Api::V1::PollPublicationsTest < ActionDispatch::IntegrationTest
  setup do
    _, @key = ApiKey.issue!(user: users(:admin), name: "poll-test")
    @poll = Poll.create!(slug: "test-poll-publication", title_en: "Poll", survey_slug: "survey",
      body_en: "## Analysis", published_at: 1.day.ago, news_release_en: "Public news", subscriber_email_en: "Private email", tweet_en: "Private tweet")
    @poll.crosstabs_json.attach(io: StringIO.new('{"schemaVersion":2}'), filename: "crosstabs.json", content_type: "application/json", identify: false)
  end

  test "public poll includes downloads and news but not launch copy" do
    get api_v1_poll_url(@poll.slug)
    assert_response :success
    payload = response.parsed_body
    assert_not payload.key?("content_kind")
    assert_includes payload.dig("poll", "news_release"), "Public news"
    assert payload.dig("poll", "downloads", "crosstabs_json")
    assert_not payload["poll"].key?("launch_copy")
    assert_not_includes response.body, "Private email"
  end

  test "French markdown downloads preserve chart source and locale" do
    markdown = "## Résultats\n\n```buildcanada-chart\n{\"data\":54}\n```"
    @poll.update!(body_fr: markdown)
    get api_v1_poll_url(@poll.slug), params: { locale: "fr" }
    url = response.parsed_body.dig("poll", "downloads", "analysis_markdown")
    assert_includes url, "locale=fr"
    get url
    assert_response :success
    assert_equal markdown, response.body
  end

  test "generated report links select French with English fallback and branded filenames" do
    @poll.update!(body_fr: "## Analyse")
    %w[analysis_pdf_en analysis_pdf_fr].each do |asset|
      @poll.public_send(asset).attach(io: StringIO.new("%PDF-1.4 #{asset}"), filename: "#{asset}.pdf", content_type: "application/pdf", identify: false,
        metadata: { source_digest: @poll.artifact_digest(asset) })
    end
    %w[en fr].each do |locale|
      get api_v1_poll_url(@poll.slug), params: { locale: locale }
      url = response.parsed_body.dig("poll", "downloads", "analysis_pdf")
      assert_includes URI(url).path, "/downloads/analysis_pdf_#{locale}"
      get url
      assert_response :success
      assert_equal "%PDF-1.4 analysis_pdf_#{locale}", response.body
      assert_includes response.headers["Content-Disposition"], "Build Canada"
      assert_includes response.headers["Content-Disposition"], @poll.published_at.to_date.iso8601
      assert_includes response.headers["Content-Disposition"], "Poll"
    end
    @poll.update!(body_fr: nil)
    get api_v1_poll_url(@poll.slug), params: { locale: "fr" }
    assert_includes response.parsed_body.dig("poll", "downloads", "analysis_pdf"), "analysis_pdf_en"
    @poll.update!(body_en: "Changed")
    get download_api_v1_poll_url(@poll.slug, asset: "analysis_pdf_en")
    assert_response :service_unavailable
    get api_v1_poll_url(@poll.slug)
    assert_not response.parsed_body.dig("poll", "downloads").key?("analysis_pdf")
  end

  test "poll index excludes memos and hides drafts" do
    get api_v1_polls_url
    assert_equal [ @poll.slug ], response.parsed_body["data"].map { |item| item["slug"] }
    @poll.update!(published_at: nil)
    get api_v1_polls_url
    assert_empty response.parsed_body["data"]
  end

  test "polls and memos have independent storage slugs and APIs" do
    memo = Memo.create!(slug: @poll.slug, title_en: "Separate memo", published_at: 1.day.ago)
    get api_v1_memo_url(memo.slug)
    assert_equal "Separate memo", response.parsed_body["title"]
    assert_not response.parsed_body.key?("poll")
    get api_v1_memos_url
    assert_includes response.parsed_body["data"].map { |row| row["title"] }, "Separate memo"
    assert_not_includes response.parsed_body["data"].map { |row| row["title"] }, @poll.title_en
    assert_not Poll.column_names.include?("endorsements_count")
    assert_not Memo.column_names.include?("survey_slug")
  end

  test "downloads become unavailable when the poll is unpublished" do
    url = download_api_v1_poll_url(@poll.slug, asset: "crosstabs_json")
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
    get download_api_v1_poll_url(@poll.slug, asset: "seo_image")
    assert_response :not_found
  end

  test "admin preview includes launch copy and API keys cannot publish polls" do
    get api_v1_poll_url(@poll.slug), headers: { "Authorization" => "Bearer #{@key}" }
    assert_equal "Private email", response.parsed_body.dig("poll", "launch_copy", "subscriber_email_markdown")
    post api_v1_polls_url, params: { poll: { slug: "new-poll", title_en: "New poll", survey_slug: "survey", published_at: 1.day.ago.iso8601 } },
      headers: { "Authorization" => "Bearer #{@key}" }, as: :json
    assert_response :created
    assert_nil Poll.find_by!(slug: "new-poll").published_at
  end
end
