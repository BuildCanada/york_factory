module PublicWebsite
  def self.url
    ENV.fetch("WEBSITE_URL", "https://www.buildcanada.com").delete_suffix("/")
  end
end
