media_feeds = [
  { name: "CBC | Top Stories News", url: "https://www.cbc.ca/cmlink/rss-topstories", publisher_name: "CBC News", publisher_domain: "cbc.ca", language: "en" },
  { name: "CTVNews.ca - Top Stories", url: "https://www.ctvnews.ca/rss/ctvnews-ca-top-stories-public-rss-1.822009", publisher_name: "CTV News", publisher_domain: "ctvnews.ca", language: "en" },
  { name: "Global News", url: "https://globalnews.ca/feed/", publisher_name: "Global News", publisher_domain: "globalnews.ca", language: "en" },
  { name: "Financial Post", url: "https://business.financialpost.com/feed/", publisher_name: "Financial Post", publisher_domain: "financialpost.com", language: "en" },
  { name: "National Post", url: "https://nationalpost.com/feed/", publisher_name: "National Post", publisher_domain: "nationalpost.com", language: "en" },
  { name: "Ottawa Citizen", url: "https://ottawacitizen.com/feed/", publisher_name: "Ottawa Citizen", publisher_domain: "ottawacitizen.com", language: "en" },
  { name: "The Province", url: "https://theprovince.com/feed/", publisher_name: "The Province", publisher_domain: "theprovince.com", language: "en" },
  { name: "La Presse - Actualites", url: "https://www.lapresse.ca/actualites/rss", publisher_name: "La Presse", publisher_domain: "lapresse.ca", language: "fr" },
  { name: "Toronto Star", url: "https://www.thestar.com/search/?f=rss&t=article&bl=2827101&l=20", publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en" },
  { name: "Toronto Star - Politics", url: "https://www.thestar.com/search/?f=rss&t=article&c=politics*&l=50&s=start_time&sd=desc", publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en" },
  { name: "Toronto Star - News", url: "https://www.thestar.com/search/?f=rss&t=article&c=news*&l=50&s=start_time&sd=desc", publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en" },
  { name: "Toronto Star - Business", url: "https://www.thestar.com/search/?f=rss&t=article&c=business*&l=50&s=start_time&sd=desc", publisher_name: "Toronto Star", publisher_domain: "thestar.com", language: "en" },
  { name: "Toronto Sun", url: "https://torontosun.com/category/news/feed", publisher_name: "Toronto Sun", publisher_domain: "torontosun.com", language: "en" }
]

media_feeds.each do |attributes|
  Warehouse::MediaFeed.find_or_create_by!(name: attributes.fetch(:name)) do |feed|
    feed.assign_attributes(attributes.merge(
      strategy: "rss",
      cadence_seconds: 300,
      enabled: true,
      next_fetch_at: Time.current
    ))
  end
end
