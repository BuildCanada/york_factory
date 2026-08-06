# Scrapes the City of Brampton's registered-candidate page
# (brampton.ca/EN/City-Hall/Election/Candidates/Pages/candidateListing.aspx)
# into one canonical body:
#
#   { "year",
#     "offices" => [ { "code", "heading", "wards", "candidates" => [...] } ] }
#
# Brampton publishes no candidate feed — the list is server-rendered inside a
# SharePoint page, so the HTML is parsed here rather than in the loader: the
# rest of the page (nav chrome, request digests, form tokens) churns on every
# request and would defeat the fetcher's checksum dedupe. Candidates are
# sorted by the page's own sort key so a change in the default sort order
# doesn't read as changed data either.
#
# Office codes ("mayor", "cc15", "pdsb15", "monavenir") and headings are
# passed through verbatim; mapping them onto races is the loader's job.
#
# A page with no office groupings at all raises — Brampton renders the office
# structure whether or not anyone has filed, so an empty parse means the
# markup moved, not that nobody is running.
class Warehouse::Source::Fetcher::BramptonCandidateList
  # The page writes "-" into every field the candidate left blank.
  BLANK = "-".freeze

  def initialize(url, year:, http: HTTPX.plugin(:follow_redirects))
    raise ArgumentError, "year is required (expected the source name to end in a year, e.g. election_brampton_2026)" if year.blank?

    @url = url
    @year = year.to_s
    @http = http
  end

  def call
    JSON.generate("year" => @year, "offices" => offices(document))
  end

  def each_download
    return enum_for(__method__) unless block_given?

    body = call
    yield Warehouse::Source::Fetcher::Download.new(
      body:,
      checksum: Digest::SHA256.hexdigest(body)
    ) { |ingestion, content| ingestion.brampton_candidates_loader.load(json_content: content) }
  end

  private

  def document
    response = @http.get(@url)
    raise "HTTP #{response.status}: #{@url}" unless response.status == 200

    body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
    body = body.scrub unless body.valid_encoding?
    Nokogiri::HTML5(body)
  end

  def offices(doc)
    groupings = doc.css("div.office-grouping")
    if groupings.empty?
      raise "Unexpected Brampton candidate page shape for #{@url}: no div.office-grouping blocks found"
    end

    groupings.map do |grouping|
      code = grouping["data-office"].to_s
      raise "Unexpected Brampton candidate page shape for #{@url}: office grouping without data-office" if code.blank?

      {
        "code" => code,
        "heading" => text(grouping.at_css(".office-heading")),
        "wards" => wards(grouping),
        "candidates" => candidates(grouping)
      }
    end
  end

  # data-wards holds the wards an office covers: ["ward-1", "ward-5"].
  def wards(grouping)
    Array.wrap(JSON.parse(grouping["data-wards"].to_s.presence || "[]"))
      .filter_map { |ward| ward.to_s[/\d+/]&.to_i }
      .sort
  rescue JSON::ParserError
    []
  end

  def candidates(grouping)
    grouping.css(".candidate-details")
      .map { |item| candidate(item) }
      .sort_by { |c| [ c["sort_key"].to_s, c["name"].to_s ] }
  end

  def candidate(item)
    socials = item.css(".box-social-info .candidate-social-link").filter_map { |link| social(link) }

    {
      "name" => candidate_name(item),
      "sort_key" => item["data-name"].to_s,
      # data-date is the filing date as MMDDYYYY; the visible text is the
      # same date as M/D/YYYY and serves as the fallback.
      "filing_date" => item["data-date"].presence,
      "filing_date_text" => labelled(item, ".filing-date"),
      "withdrawn" => item.classes.include?("candidate-withdrawn"),
      "qualifying_address" => labelled(item, ".box-qualify-info", "Qualifying Address"),
      "cell_phone" => labelled(item, ".box-qualify-info", "Cell Phone"),
      "campaign_address" => labelled(item, ".box-campaign-info", "Campaign Address"),
      "campaign_phone" => labelled(item, ".box-campaign-info", "Campaign Phone"),
      "email" => socials.find { |s| s["name"] == "email" }&.dig("url")&.delete_prefix("mailto:"),
      "website" => socials.find { |s| s["name"] == "web" }&.dig("url"),
      "socials" => socials.reject { |s| s["name"] == "email" }
    }
  end

  # The name cell is "Last, First", with a trailing "(Withdrawn)" span and a
  # screen-reader note for withdrawn candidates. Single-name candidates get
  # the page's "-" blank marker as their given name ("Gursimranjit Singh, -").
  def candidate_name(item)
    cell = item.at_css(".candidate-name")
    return nil if cell.nil?

    cell = cell.dup
    cell.css("span").each(&:remove)
    text(cell)&.sub(/,\s*#{Regexp.escape(BLANK)}\z/, "")
  end

  # Detail fields render as "<span>Label: </span>value"; the value is what's
  # left once the label span is gone.
  def labelled(item, container_selector, label = nil)
    container = item.at_css(container_selector)
    return nil if container.nil?

    node = if label
      container.css("div").find { |div| div.at_css("span")&.text.to_s.strip.chomp(":").casecmp?(label) }
    else
      container
    end
    return nil if node.nil?

    node = node.dup
    node.css("span").each(&:remove)
    text(node)
  end

  # Link rows without an <a> are the page's "No site provided." placeholders.
  def social(link)
    anchor = link.at_css("a[href]")
    return nil if anchor.nil?

    { "name" => social_name(link, anchor), "url" => anchor["href"].to_s.strip }
  end

  # The Font Awesome icon class is the most stable label ("fab fa-instagram",
  # "fa-brands fa-square-x-twitter"); the visible link text is the fallback.
  # Names are normalized onto the same vocabulary the Toronto feed publishes
  # ("web", "twitter", ...) so consumers can key off one set.
  ICON_STYLE_CLASSES = %w[fa-brands fa-solid fa-regular fa-light fa-thin fa-duotone fa-sharp fa-fw].freeze
  ICON_ALIASES = { "globe" => "web", "envelope" => "email", "x-twitter" => "twitter" }.freeze

  def social_name(link, anchor)
    icon = link.at_css("i")&.classes.to_a
      .grep(/\Afa-/)
      .reject { |c| ICON_STYLE_CLASSES.include?(c) }
      .first
      &.delete_prefix("fa-")
      &.delete_prefix("square-")

    return text(link.at_css(".social-link-text") || anchor).to_s.downcase.presence || "link" if icon.nil?

    ICON_ALIASES.fetch(icon, icon)
  end

  def text(node)
    return nil if node.nil?

    value = node.text.to_s.gsub(/\s+/, " ").strip
    return nil if value.blank? || value == BLANK

    value
  end
end
