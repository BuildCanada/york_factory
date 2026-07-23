# Downloads the City of Toronto's registered-candidate JSON feeds (the data
# behind toronto.ca/city-government/elections/candidate-list/) and combines
# them into one canonical body:
#
#   { "year", "mayor" (candidates), "councillor" (wards),
#     "trustee" (school boards), "withdrawn" (candidates) }
#
# Only the payload keys are kept — each feed wraps its data with a "seq"
# generation timestamp that changes on every republish, which would defeat
# the fetcher's checksum dedupe if included.
#
# The councillor filename really is spelled "councilor" upstream. The trustee
# and withdrawn feeds may not exist early in an election cycle, so a 404
# there reads as empty; mayor and councillor 404s raise.
class Warehouse::Source::Fetcher::TorontoCandidateList
  def initialize(url, year:, http: HTTPX.plugin(:follow_redirects))
    raise ArgumentError, "year is required (expected the source name to end in a year, e.g. election_toronto_2026)" if year.blank?

    @url = url.chomp("/")
    @year = year.to_s
    @http = http
  end

  def call
    JSON.generate(
      "year" => @year,
      "mayor" => fetch_feed("mayorCandidates_#{@year}.json", "candidates"),
      "councillor" => fetch_feed("councilorCandidates_#{@year}.json", "ward"),
      "trustee" => fetch_feed("trusteeCandidates_#{@year}.json", "schoolBoard", optional: true),
      "withdrawn" => fetch_feed("withdrawnCandidates_#{@year}.json", "candidates", optional: true)
    )
  end

  private

  def fetch_feed(filename, payload_key, optional: false)
    file_url = "#{@url}/#{filename}"
    response = @http.get(file_url)

    return [] if optional && response.status == 404
    raise "HTTP #{response.status}: #{file_url}" unless response.status == 200

    # The server omits a charset, so HTTPX hands back BINARY; the payload is
    # UTF-8 JSON, sometimes with a BOM.
    body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
    body = body.scrub unless body.valid_encoding?
    parsed = JSON.parse(body.delete_prefix("\uFEFF"))
    payload = parsed[payload_key]
    unless payload.is_a?(Array)
      raise "Unexpected Toronto candidate feed shape for #{file_url}: missing \"#{payload_key}\" array"
    end

    payload
  end
end
