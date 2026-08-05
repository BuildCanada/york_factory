module Search
  module Media
    class FeedCatalog
      Feed = Data.define(:name, :url, :publisher_name, :publisher_domain, :language)

      FEEDS = [
        Feed.new(name: "CBC | Top Stories News", url: "https://www.cbc.ca/cmlink/rss-topstories", publisher_name: "CBC News", publisher_domain: "cbc.ca", language: "en"),
        Feed.new(name: "CTVNews.ca - Top Stories", url: "https://www.ctvnews.ca/rss/ctvnews-ca-top-stories-public-rss-1.822009", publisher_name: "CTV News", publisher_domain: "ctvnews.ca", language: "en"),
        Feed.new(name: "Global News", url: "https://globalnews.ca/feed/", publisher_name: "Global News", publisher_domain: "globalnews.ca", language: "en"),
        Feed.new(name: "Financial Post", url: "https://business.financialpost.com/feed/", publisher_name: "Financial Post", publisher_domain: "financialpost.com", language: "en"),
        Feed.new(name: "National Post", url: "https://nationalpost.com/feed/", publisher_name: "National Post", publisher_domain: "nationalpost.com", language: "en"),
        Feed.new(name: "Ottawa Citizen", url: "https://ottawacitizen.com/feed/", publisher_name: "Ottawa Citizen", publisher_domain: "ottawacitizen.com", language: "en"),
        Feed.new(name: "The Province", url: "https://theprovince.com/feed/", publisher_name: "The Province", publisher_domain: "theprovince.com", language: "en"),
        Feed.new(name: "La Presse - Actualites", url: "https://www.lapresse.ca/actualites/rss", publisher_name: "La Presse", publisher_domain: "lapresse.ca", language: "fr"),
        Feed.new(name: "Toronto Star", url: "https://www.thestar.com/search/?f=rss&t=article&bl=2827101&l=20", publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en"),
        Feed.new(name: "Toronto Star - Politics", url: "https://www.thestar.com/search/?f=rss&t=article&c=politics*&l=50&s=start_time&sd=desc", publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en"),
        Feed.new(name: "Toronto Star - News", url: "https://www.thestar.com/search/?f=rss&t=article&c=news*&l=50&s=start_time&sd=desc", publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en"),
        Feed.new(name: "Toronto Star - Business", url: "https://www.thestar.com/search/?f=rss&t=article&c=business*&l=50&s=start_time&sd=desc", publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en"),
        Feed.new(name: "Toronto Sun", url: "https://torontosun.com/category/news/feed", publisher_name: "Toronto Sun", publisher_domain: "torontosun.com", language: "en")
      ].freeze

      DOMAIN_ALIASES = {
        "cbc.ca" => "cbc.ca",
        "www.cbc.ca" => "cbc.ca",
        "ctvnews.ca" => "ctvnews.ca",
        "www.ctvnews.ca" => "ctvnews.ca",
        "globalnews.ca" => "globalnews.ca",
        "www.globalnews.ca" => "globalnews.ca",
        "financialpost.com" => "financialpost.com",
        "www.financialpost.com" => "financialpost.com",
        "business.financialpost.com" => "financialpost.com",
        "nationalpost.com" => "nationalpost.com",
        "www.nationalpost.com" => "nationalpost.com",
        "theglobeandmail.com" => "theglobeandmail.com",
        "www.theglobeandmail.com" => "theglobeandmail.com",
        "ottawacitizen.com" => "ottawacitizen.com",
        "www.ottawacitizen.com" => "ottawacitizen.com",
        "theprovince.com" => "theprovince.com",
        "www.theprovince.com" => "theprovince.com",
        "lapresse.ca" => "lapresse.ca",
        "www.lapresse.ca" => "lapresse.ca",
        "thestar.com" => "thestar.com",
        "www.thestar.com" => "thestar.com",
        "torontosun.com" => "torontosun.com",
        "www.torontosun.com" => "torontosun.com"
      }.freeze

      PUBLISHERS = FEEDS.index_by(&:publisher_domain).transform_values do |feed|
        { "name" => feed.publisher_name, "domain" => feed.publisher_domain }.freeze
      end.merge(
        "theglobeandmail.com" => { "name" => "The Globe and Mail", "domain" => "theglobeandmail.com" }.freeze
      ).freeze

      class << self
        def publisher_for(host)
          canonical_domain = DOMAIN_ALIASES[host.to_s.downcase.delete_suffix(".")]
          PUBLISHERS[canonical_domain]
        end

        def provision!(source_class: Search::Source, cadence_seconds: 300)
          FEEDS.map do |feed|
            source = source_class.find_or_initialize_by(name: feed.name)
            source.assign_attributes(
              realm: "media",
              strategy: "rss",
              url: feed.url,
              cadence_seconds: cadence_seconds,
              configuration: source.configuration.to_h.except("fallback_url").merge(
                "publisher_name" => feed.publisher_name,
                "publisher_domain" => feed.publisher_domain,
                "language" => feed.language
              ),
              enabled: true,
              next_fetch_at: source.next_fetch_at || Time.current
            )
            source.save!
            source
          end
        end
      end
    end
  end
end
