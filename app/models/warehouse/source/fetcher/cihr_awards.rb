# Downloads the CIHR funding-decisions Solr result set as plain JSON. The
# public search page normally asks this endpoint for JSONP and supplies a
# browser session cookie; neither is required for the JSON API response.
class Warehouse::Source::Fetcher::CihrAwards
  Download = Data.define(:io, :checksum)
  DEFAULT_ROWS_PER_PAGE = 1_000
  MAX_PAGES = 200

  FIELDS = %w[
    name pinamesdelim country region orgnameinp2 orgtype programname2
    programtype2 instname2 partnername competitiondate prcname2 approvedterm
    projecttitle cihramount2 cihrequipment2 id conames supnames abstract
    keyworddelim conamesdelim supnamesdelim orgnamerin2 deptnamerin2
    primaryinstname2 theme2 approvedterm2 cihrcontribution2 partnerfunding2
    partnerapplicant2 partnerkind2 allnames
  ].freeze

  def initialize(url, http: HTTPX.plugin(:follow_redirects),
                 rows_per_page: DEFAULT_ROWS_PER_PAGE, max_pages: MAX_PAGES)
    @url = url
    @http = http
    @rows_per_page = Integer(rows_per_page)
    @max_pages = Integer(max_pages)
    raise ArgumentError, "rows_per_page must be positive" unless @rows_per_page.positive?
    raise ArgumentError, "max_pages must be positive" unless @max_pages.positive?
  end

  def call
    output = Tempfile.new([ "cihr-awards", ".ndjson" ])
    output.binmode
    digest = Digest::SHA256.new
    expected_count = nil
    written_count = 0
    previous_id = nil
    page = 0

    loop do
      raise "CIHR pagination exceeded #{@max_pages} pages: #{@url}" if page >= @max_pages

      response = fetch_page(start: page * @rows_per_page)
      expected_count ||= response.fetch("numFound")
      if response.fetch("numFound") != expected_count
        raise "CIHR result count changed during pagination: #{expected_count} to #{response.fetch("numFound")}"
      end

      page_documents = response.fetch("docs")
      page_documents.each do |document|
        id = document.fetch("id").to_s
        if previous_id && id <= previous_id
          problem = id == previous_id ? "duplicate award ids" : "out-of-order award id"
          raise "CIHR returned #{problem}: #{id}"
        end

        line = "#{canonical_json(document)}\n"
        output.write(line)
        digest.update(line)
        previous_id = id
        written_count += 1
      end

      break if written_count >= expected_count
      raise "CIHR response ended after #{written_count} of #{expected_count} documents" if page_documents.empty?

      page += 1
    end

    if written_count != expected_count
      raise "CIHR returned #{written_count} documents but reported #{expected_count}"
    end

    output.flush
    output.rewind
    Download.new(io: output, checksum: digest.hexdigest)
  rescue
    output&.close!
    raise
  end

  private

  def fetch_page(start:)
    response = @http.post(
      endpoint,
      headers: {
        "Accept" => "application/json",
        "Content-Type" => "application/x-www-form-urlencoded",
        "X-Requested-With" => "XMLHttpRequest"
      },
      body: Rack::Utils.build_query(
        "q" => "*:*",
        "start" => start,
        "rows" => @rows_per_page,
        "sort" => "id asc",
        "fl" => FIELDS.join(","),
        "core" => "fdd_en",
        "wt" => "json",
        "json.nl" => "map"
      )
    )
    raise "HTTP #{response.status}: #{endpoint}" unless response.status == 200

    parsed = JSON.parse(response.body.to_s.delete_prefix("\uFEFF"))
    solr_response = parsed["response"]
    unless solr_response.is_a?(Hash) && solr_response["numFound"].is_a?(Integer) && solr_response["docs"].is_a?(Array)
      raise "Unexpected CIHR response for #{endpoint}: #{response.body.to_s.truncate(200)}"
    end
    unless solr_response["docs"].all? { |document| document.is_a?(Hash) && document["id"].present? }
      raise "CIHR response contains a document without an id"
    end

    solr_response
  rescue JSON::ParserError => error
    raise "Invalid CIHR JSON for #{endpoint}: #{error.message}"
  end

  def canonical_json(value)
    JSON.generate(canonical_value(value))
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [ key, canonical_value(value.fetch(key)) ] }
    when Array
      value.map { |item| canonical_value(item) }
    else
      value
    end
  end

  def endpoint
    uri = URI.parse(@url)
    path = if uri.path.include?("/p/")
      "#{uri.path.sub(%r{/p/.*\z}, "")}/sq"
    elsif uri.path.end_with?("/sq", "/sq/")
      uri.path.sub(%r{/\z}, "")
    else
      "#{File.dirname(uri.path)}/sq"
    end
    uri.path = path
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  end
end
