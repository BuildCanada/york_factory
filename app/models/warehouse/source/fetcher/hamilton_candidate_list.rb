# Scrapes the City of Hamilton's certified-candidate page
# (hamilton.ca/city-council/municipal-election/candidates-third-party-advertisers/candidates)
# into one canonical body:
#
#   { "year",
#     "offices" => [ { "section", "label", "candidates" => [...] } ] }
#
# Hamilton publishes no candidate feed. Everything lives on one page as three
# tabs (#nav-mayor-content, #nav-councillor-content, #nav-trustee-content);
# councillor and trustee tabs group candidates into accordion items whose
# button text names the district ("Ward 1", "Wards 5 & 10 - English Public").
# Parsing happens here rather than in the loader so checksum dedupe and the R2
# archive see only candidate data, not the ~1MB of page chrome around it.
# Candidates are sorted by name so a reordered table doesn't read as changed
# data either. Section labels are passed through verbatim; mapping them onto
# races is the loader's job.
#
# Two fields on the page are deliberately not collected:
#
#   * Email — obfuscated by Cloudflare (`__cf_email__`) specifically to stop
#     address harvesting. We honour that: an obfuscated cell reads as nil.
#     The public API never exposed candidate email anyway.
#   * Address — candidates' home addresses. There is nowhere in the schema for
#     them and no use for them, so they are not extracted.
#
# A page with none of the three tab containers raises — Hamilton renders the
# office structure whether or not anyone has filed, so an empty parse means
# the markup moved, not that nobody is running.
class Warehouse::Source::Fetcher::HamiltonCandidateList
  # The page writes "-" into every cell the candidate left blank.
  BLANK = "-".freeze

  SECTIONS = %w[mayor councillor trustee].freeze

  def initialize(url, year:, http: HTTPX.plugin(:follow_redirects))
    raise ArgumentError, "year is required (expected the source name to end in a year, e.g. election_hamilton_2026)" if year.blank?

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
    ) { |ingestion, content| ingestion.hamilton_candidates_loader.load(json_content: content) }
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
    containers = SECTIONS.filter_map do |section|
      container = doc.at_css("##{tab_id(section)}")
      [ section, container ] if container
    end

    if containers.empty?
      raise "Unexpected Hamilton candidate page shape for #{@url}: none of " \
        "#{SECTIONS.map { |s| "##{tab_id(s)}" }.join(", ")} found"
    end

    containers.flat_map { |section, container| section_offices(section, container) }
  end

  def tab_id(section)
    "nav-#{section}-content"
  end

  # Councillor and trustee tabs group districts into accordion items; the
  # mayor tab holds its table directly.
  def section_offices(section, container)
    items = container.css(".accordion-item")
    return items.map { |item| office(section, text(item.at_css(".accordion-item--toggle")), item.at_css("table")) } if items.any?

    tables = container.css("table")
    return [ office(section, nil, nil) ] if tables.empty?

    tables.map { |table| office(section, nil, table) }
  end

  # An accordion item with no table is a district nobody has filed in — a real
  # state on the page today, and one worth carrying through as an empty race.
  def office(section, label, table)
    { "section" => section, "label" => label, "candidates" => candidates(table) }
  end

  # The tables are hand-authored and inconsistent: most put their header row in
  # a <thead> of <th>, at least one uses a plain <td> row inside <tbody>. The
  # header row is located by content rather than by markup, both so its labels
  # can drive column lookup and so it never reads as a candidate named "Name".
  def candidates(table)
    return [] if table.nil?

    rows = table.css("tr")
    header = rows.find { |row| header_row?(row) }
    columns = header ? column_indexes(header) : fallback_columns
    name_index = columns["name"] || 0

    (rows.to_a - [ header ]).filter_map { |row| candidate(row, columns, name_index) }
      .sort_by { |candidate| candidate["name"].to_s }
  end

  # Any cell, not just the first — the "Name" column is not always leftmost.
  def header_row?(row)
    row.css("th, td").any? { |cell| label(cell) == "name" }
  end

  # Columns are read by header name so an upstream reorder can't silently
  # shift phone numbers into the name field.
  def column_indexes(row)
    row.css("th, td").each_with_index.to_h { |cell, index| [ label(cell), index ] }
  end

  # Every table on the page has used this order; a table that loses its header
  # row falls back to it rather than dropping its candidates.
  FALLBACK_COLUMNS = { "name" => 0, "address" => 1, "phone" => 2, "email" => 3 }.freeze

  def fallback_columns
    Rails.logger.warn "[HamiltonCandidateList] Candidate table with no \"Name\" header row; " \
      "assuming #{FALLBACK_COLUMNS.keys.join(", ")} column order"
    FALLBACK_COLUMNS
  end

  def label(cell)
    cell&.text.to_s.gsub(/[[:space:]]+/, " ").strip.downcase.chomp(":")
  end

  def candidate(row, columns, name_index)
    cells = row.css("td")
    name = text(cells[name_index])
    return nil if name.nil?

    { "name" => name, "phone" => cell(cells, columns["phone"]), "email" => email(cells, columns["email"]) }
  end

  def cell(cells, index)
    index.nil? ? nil : text(cells[index])
  end

  # Cloudflare replaces the address with a "[email protected]" placeholder
  # carrying the encoded value in data-cfemail. Left undecoded on purpose.
  def email(cells, index)
    node = index.nil? ? nil : cells[index]
    return nil if node.nil? || node.at_css(".__cf_email__, [data-cfemail]")

    value = text(node)
    value&.include?("@") ? value : nil
  end

  def text(node)
    return nil if node.nil?

    value = node.text.to_s.gsub(/[[:space:]]+/, " ").strip
    return nil if value.blank? || value == BLANK

    value
  end
end
