# Downloads a World Bank API indicator across all pages and normalizes the
# result to one canonical JSON array (sorted by country and year), so the
# fetcher's checksum dedupe and R2 archive see a stable, replayable body.
#
# World Bank responses are a two-element array: [envelope, rows], where the
# envelope carries {"page", "pages", "per_page", "total"}.
class Warehouse::Source::Fetcher::WorldBankDownload
  MAX_PAGES = 50

  def initialize(url, http: HTTPX.plugin(:follow_redirects))
    @url = url
    @http = http
  end

  def call
    rows = []
    page = 1

    loop do
      envelope, page_rows = fetch_page(page)
      rows.concat(Array(page_rows))
      total_pages = envelope["pages"].to_i
      break if page >= total_pages
      page += 1
      raise "World Bank pagination exceeded #{MAX_PAGES} pages: #{@url}" if page > MAX_PAGES
    end

    rows.sort_by! { |row| [ row["countryiso3code"].to_s, row["date"].to_s ] }
    JSON.generate(rows)
  end

  private

  def fetch_page(page)
    separator = @url.include?("?") ? "&" : "?"
    page_url = "#{@url}#{separator}page=#{page}"
    response = @http.get(page_url)
    raise "HTTP #{response.status}: #{page_url}" unless response.status == 200

    # The API intermittently prepends a UTF-8 BOM to responses.
    parsed = JSON.parse(response.body.to_s.delete_prefix("\uFEFF"))
    envelope = parsed.first
    unless envelope.is_a?(Hash) && envelope["pages"]
      # The API reports errors as [{"message": [...]}] with a 200 status.
      raise "Unexpected World Bank response for #{page_url}: #{response.body.to_s.truncate(200)}"
    end

    [ envelope, parsed[1] ]
  end
end
