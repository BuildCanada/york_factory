require "test_helper"

class PublicWebsiteTest < ActiveSupport::TestCase
  test "configured public URL is shared by previews feeds reports and bot identification" do
    previous = ENV["WEBSITE_URL"]
    ENV["WEBSITE_URL"] = "https://www.example.org/"
    assert_equal "https://www.example.org", PublicWebsite.url
    assert_equal PublicWebsite.url, Object.new.extend(ApplicationHelper).website_url
    poll = Poll.new(slug: "configured-url", title_en: "Poll", survey_slug: "survey", body_en: "Analysis")
    renderer = Polls::AnalysisPdf.new(poll, "en")
    assert_equal "https://www.example.org/polls/configured-url", renderer.send(:poll_url)
    assert_includes renderer.document_html, renderer.send(:css_string, "www.example.org/polls/configured-url")
    feed = Nokogiri::XML(PublicationFeed.new("all").render)
    assert_equal "https://www.example.org", feed.at_xpath("//channel/link").text
    assert_equal "https://www.example.org/feeds/all.xml", feed.at_xpath("//atom:link", "atom" => "http://www.w3.org/2005/Atom")["href"]
    client = Metrics::SubstackClient.new(base_url: "https://example.substack.com")
    assert_equal "BuildCanadaBot/1.0 (+https://www.example.org)", client.send(:headers)["User-Agent"]
    digest = poll.artifact_digest("analysis_pdf_en")
    ENV.delete("WEBSITE_URL")
    assert_equal "https://www.buildcanada.com", PublicWebsite.url
    assert_not_equal digest, poll.artifact_digest("analysis_pdf_en")
  ensure
    previous.nil? ? ENV.delete("WEBSITE_URL") : ENV["WEBSITE_URL"] = previous
  end
end
