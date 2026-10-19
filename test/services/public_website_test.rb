require "test_helper"

class PublicWebsiteTest < ActiveSupport::TestCase
  test "configured public URL is shared by previews feeds and bot identification" do
    previous = ENV["WEBSITE_URL"]
    ENV["WEBSITE_URL"] = "https://www.example.org/"
    assert_equal "https://www.example.org", PublicWebsite.url
    assert_equal PublicWebsite.url, Object.new.extend(ApplicationHelper).website_url
    feed = Nokogiri::XML(PublicationFeed.new("all").render)
    assert_equal "https://www.example.org", feed.at_xpath("//channel/link").text
    assert_equal "https://www.example.org/feeds/all.xml", feed.at_xpath("//atom:link", "atom" => "http://www.w3.org/2005/Atom")["href"]
    client = Metrics::SubstackClient.new(base_url: "https://example.substack.com")
    assert_equal "BuildCanadaBot/1.0 (+https://www.example.org)", client.send(:headers)["User-Agent"]
    ENV.delete("WEBSITE_URL")
    assert_equal "https://www.buildcanada.com", PublicWebsite.url
  ensure
    previous.nil? ? ENV.delete("WEBSITE_URL") : ENV["WEBSITE_URL"] = previous
  end
end
