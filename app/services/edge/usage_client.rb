module Edge
  # The Worker's signed usage endpoints (data-api workers/edge/src/internal.ts):
  #
  #   GET {edge}/internal/keys/{digest}/usage                  the KeyDO's bucket, quota and unflushed units
  #   GET {edge}/internal/accounts/{account_id}/usage?month=   the AccountDO's month total and day totals
  #
  # Signed with Edge::Signature like the key pushes. Answers nil when the
  # edge isn't configured or can't be reached, so callers degrade to the
  # rollup alone.
  class UsageClient
    TIMEOUT = { connect_timeout: 2, operation_timeout: 5 }.freeze

    def initialize(http: nil, url: Edge.url, secret: Edge.secret)
      @http = http
      @url = url.to_s.chomp("/")
      @secret = secret
    end

    def configured? = @url.present? && @secret.present?

    def key(api_key) = get("/internal/keys/#{api_key.token_digest}/usage")

    # {"account_id", "month" => {"period", "units", "requests"}, "days" => [{"period" => "YYYY-MM-DD", ...}]}
    def account(account, month:) = get("/internal/accounts/#{account.id}/usage?month=#{month}")

    # {Date => units} from #account.
    def account_days(account, month:)
      answer = account(account, month:) or return nil

      Array(answer["days"]).each_with_object({}) do |day, out|
        date = Date.iso8601(day["period"].to_s) rescue next
        out[date] = day["units"].to_f.round
      end
    end

    private

    def get(path)
      return nil unless configured?

      headers = Signature.headers(method: "GET", path:, body: "", secret: @secret)
      response = http.request("GET", "#{@url}#{path}", headers:)
      return nil unless response.respond_to?(:status) && response.status.to_i == 200

      JSON.parse(response.body.to_s)
    rescue JSON::ParserError, HTTPX::Error, SocketError, SystemCallError, Timeout::Error, IOError => error
      Rails.logger.warn("[Edge::UsageClient] #{path.split('?').first}: #{error.class}")
      nil
    end

    def http = @http ||= HTTPX.with(timeout: TIMEOUT)
  end
end
