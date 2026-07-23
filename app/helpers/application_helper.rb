module ApplicationHelper
  # Base URL of the public Build Canada website (TradingPost / Next.js).
  # Overridable via WEBSITE_URL for non-production environments.
  def website_url
    ENV.fetch("WEBSITE_URL", "https://www.buildcanada.com")
  end

  # Draft preview link for admin content.
  #
  # The website gates draft rendering on the visitor being a signed-in admin
  # (OAuth via auth.buildcanada.com), rather than the old ?secret= query param.
  # Routing through /api/auth/login kicks off that OAuth flow and redirects back
  # to the content path, where the draft renders with a preview banner.
  def preview_url(path)
    "#{website_url}/api/auth/login?redirect=#{path}"
  end
end
