require "test_helper"
require "rss"

class Api::V1::PublicationFeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @poll = Poll.create!(slug: "rss-poll", survey_slug: "survey", title_en: 'Polling & "Canada" <today>',
      published_at: 1.hour.ago, body_en: "## Public findings\n\nA finding.\n\n```buildcanada-chart\n{\"secretDataset\":1}\n```",
      subscriber_email_en: "Private launch copy")
    Poll.create!(slug: "rss-scheduled", survey_slug: "survey", title_en: "Scheduled poll", published_at: 1.day.from_now)
    Poll.create!(slug: "rss-draft", survey_slug: "survey", title_en: "Draft poll")
  end

  test "combined RSS includes public content with escaped text stable IDs and canonical links" do
    get api_v1_publication_feed_url(kind: "all", format: :xml), params: { preview: "true", hidden: "true" }
    assert_response :success
    assert_equal "application/rss+xml", response.media_type
    feed = RSS::Parser.parse(response.body, true)
    assert_equal "Build Canada", feed.channel.title
    items = feed.items
    assert_equal items.map(&:pubDate).sort.reverse, items.map(&:pubDate)
    assert_includes items.map(&:link), "https://www.buildcanada.com/memos/housing-crisis-memo"
    assert_includes items.map(&:link), "https://www.buildcanada.com/toronto/memos/toronto-transit-memo"
    assert_includes items.map(&:link), "https://www.buildcanada.com/posts/first-post"
    item = items.find { |i| i.link.end_with?("/polls/rss-poll") }
    assert_equal @poll.title_en, item.title
    assert_equal "urn:buildcanada:poll:#{@poll.id}", item.guid.content
    assert_equal false, item.guid.isPermaLink
    assert_includes item.description, "Public findings"
    assert_not_includes response.body, "secretDataset"
    %w[rss-scheduled rss-draft hidden-post draft-post draft-memo].each { |slug| assert_not_includes response.body, "/#{slug}<" }
    assert_not_includes response.body, "Private launch copy"
    assert_equal [ "max-age=60", "public" ], response.headers["Cache-Control"].split(", ").sort
    doc = Nokogiri::XML(response.body) { |config| config.strict }
    assert_equal "https://www.buildcanada.com/feeds/all.xml", doc.at_xpath("//atom:link", "atom" => "http://www.w3.org/2005/Atom")["href"]
  end

  test "individual feeds only contain their own type and never expose unpublished items" do
    %w[memos posts polls].each do |kind|
      get api_v1_publication_feed_url(kind: kind, format: :xml)
      assert_response :success
      feed = RSS::Parser.parse(response.body, true)
      assert feed.items.any?
      assert feed.items.all? { |item| item.categories.first.content == kind }
    end
    @poll.update!(published_at: nil)
    get api_v1_publication_feed_url(kind: "polls", format: :xml)
    assert_not_includes response.body, "/polls/rss-poll"
  end

  test "unknown feeds are not found" do
    get api_v1_publication_feed_url(kind: "private", format: :xml)
    assert_response :not_found
  end
end
