# Downloads Statistics Canada WDS vector series and normalizes the result to
# one canonical JSON array (sorted by vector id and reference period), so the
# fetcher's checksum dedupe and R2 archive see a stable, replayable body.
#
# The source URL encodes the request as query params on the WDS endpoint:
#   https://.../getDataFromVectorsAndLatestNPeriods?vectors=96730402,96730403&latestN=80
# The WDS API itself takes a JSON POST body: [{"vectorId": 96730402, "latestN": 80}].
class Warehouse::Source::Fetcher::StatcanVectors
  DEFAULT_LATEST_N = 100

  def initialize(url, http: HTTPX.plugin(:follow_redirects))
    @url = url
    @http = http
  end

  def call
    response = @http.post(
      endpoint,
      headers: { "Content-Type" => "application/json" },
      body: JSON.generate(request_body)
    )
    raise "HTTP #{response.status}: #{endpoint}" unless response.status == 200

    items = JSON.parse(response.body.to_s.delete_prefix("\uFEFF"))

    rows = items.flat_map do |item|
      unless item["status"] == "SUCCESS"
        raise "StatCan WDS returned #{item["status"]} for #{endpoint}: #{item.to_json.truncate(200)}"
      end

      object = item.fetch("object")
      vector_id = object.fetch("vectorId")
      object.fetch("vectorDataPoint").filter_map do |point|
        next if point["value"].nil?

        {
          "vectorId" => vector_id,
          "refPer" => point.fetch("refPer"),
          "value" => point.fetch("value").to_f
        }
      end
    end

    rows.sort_by! { |row| [ row["vectorId"], row["refPer"] ] }
    JSON.generate(rows)
  end

  private

  def endpoint
    @url.split("?").first
  end

  def request_body
    params = Rack::Utils.parse_query(URI.parse(@url).query.to_s)
    vector_ids = params.fetch("vectors", "").split(",").map { |v| Integer(v.strip) }
    raise "No vectors param in StatCan source url: #{@url}" if vector_ids.empty?

    latest_n = Integer(params.fetch("latestN", DEFAULT_LATEST_N))
    vector_ids.map { |id| { "vectorId" => id, "latestN" => latest_n } }
  end
end
