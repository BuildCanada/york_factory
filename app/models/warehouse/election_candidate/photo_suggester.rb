# Collects portrait *suggestions* for a candidate from public sources and
# stores them in photo_suggestions for admin review — nothing is ever
# published automatically. An admin accepts a suggestion (or uploads a photo
# by hand) in the admin elections UI, which is both a quality filter (many
# og:images are logos or share cards, and Wikipedia matches on a common name
# can be the wrong person entirely) and a rights check.
#
# Sources:
#   - Wikipedia REST summary for the candidate's name: lead image, page URL,
#     and short description (so the reviewer can spot name collisions).
#   - The campaign site's og:image / twitter:image, when a website is on file.
class Warehouse::ElectionCandidate::PhotoSuggester < ActiveRecord::AssociatedObject
  performs :suggest

  WIKIPEDIA_SUMMARY_URL = "https://en.wikipedia.org/api/rest_v1/page/summary/".freeze
  USER_AGENT = "YorkFactory/1.0 (buildcanada.com; candidate photo suggestions)".freeze

  def suggest(http: HTTPX.plugin(:follow_redirects))
    suggestions = [ wikipedia_suggestion(http), website_suggestion(http) ].compact
    election_candidate.update!(photo_suggestions: suggestions)
    suggestions
  end

  private

  def wikipedia_suggestion(http)
    title = URI.encode_uri_component(election_candidate.display_name.tr(" ", "_"))
    response = http.get("#{WIKIPEDIA_SUMMARY_URL}#{title}", headers: { "user-agent" => USER_AGENT })
    return nil unless response.status == 200

    summary = JSON.parse(response.body.to_s)
    # Disambiguation pages mean the name alone is ambiguous — a lead image
    # from one would be arbitrary.
    return nil unless summary["type"] == "standard"

    image_url = summary.dig("originalimage", "source") || summary.dig("thumbnail", "source")
    return nil if image_url.blank?

    {
      "source" => "wikipedia",
      "image_url" => image_url,
      "page_url" => summary.dig("content_urls", "desktop", "page"),
      "note" => summary["description"],
      "fetched_at" => Time.current.iso8601
    }
  rescue => e
    Rails.logger.warn "[PhotoSuggester] Wikipedia lookup failed for #{election_candidate.full_name}: #{e.message}"
    nil
  end

  def website_suggestion(http)
    website = election_candidate.website
    return nil if website.blank?

    response = http.get(website, headers: { "user-agent" => USER_AGENT })
    return nil unless response.status == 200

    html = Nokogiri::HTML(response.body.to_s)
    content = html.at_css('meta[property="og:image"], meta[name="og:image"], ' \
      'meta[name="twitter:image"], meta[property="twitter:image"]')&.[]("content")
    return nil if content.blank?

    {
      "source" => "campaign_site",
      "image_url" => URI.join(website, content).to_s,
      "page_url" => website,
      "note" => "og:image from campaign site — often a logo or share card, check before using",
      "fetched_at" => Time.current.iso8601
    }
  rescue => e
    Rails.logger.warn "[PhotoSuggester] Website lookup failed for #{election_candidate.full_name}: #{e.message}"
    nil
  end
end
