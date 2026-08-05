require "test_helper"

class Search::Media::FeedCatalogTest < ActiveSupport::TestCase
  test "contains each configured feed exactly once" do
    feeds = Search::Media::FeedCatalog::FEEDS

    assert_equal 13, feeds.size
    assert_equal feeds.map(&:url).uniq, feeds.map(&:url)
    assert_includes feeds.map(&:url), "https://nationalpost.com/feed/"
    assert_includes feeds.map(&:url), "https://www.cbc.ca/cmlink/rss-topstories"
    assert_includes feeds.map(&:url), "https://torontosun.com/category/news/feed"
    assert_includes feeds.map(&:url), "https://www.thestar.com/search/?f=rss&t=article&bl=2827101&l=20"
    assert_includes feeds.map(&:url), "https://www.thestar.com/search/?f=rss&t=article&c=politics*&l=50&s=start_time&sd=desc"
  end

  test "maps publisher aliases to canonical publishers" do
    assert_equal(
      { "name" => "Financial Post", "domain" => "financialpost.com" },
      Search::Media::FeedCatalog.publisher_for("business.financialpost.com")
    )
    assert_equal(
      { "name" => "The Globe and Mail", "domain" => "theglobeandmail.com" },
      Search::Media::FeedCatalog.publisher_for("www.theglobeandmail.com")
    )
  end

  test "provisions sources idempotently" do
    assert_difference -> { Search::Source.count }, 13 do
      Search::Media::FeedCatalog.provision!
    end

    assert_no_difference -> { Search::Source.count } do
      Search::Media::FeedCatalog.provision!
    end

    source = Search::Source.find_by!(name: "National Post")
    assert_equal "media", source.realm
    assert_equal "rss", source.strategy
    assert_equal "nationalpost.com", source.configuration.fetch("publisher_domain")

    toronto_star = Search::Source.find_by!(name: "Toronto Star")
    assert_equal "https://www.thestar.com/search/?f=rss&t=article&bl=2827101&l=20", toronto_star.url
    assert_not toronto_star.configuration.key?("fallback_url")
  end
end
