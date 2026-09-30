# Cloudflare Workers Analytics Engine's SQL API, for the edge Worker's
# request points (dataset data_api_requests; docs/public-interface-design.md
# §6.3, the WS-H contract in data-api workers/edge/README.md, "Metering"):
#
#   POST https://api.cloudflare.com/client/v4/accounts/{account_id}/analytics_engine/sql
#   Authorization: Bearer <token with Account Analytics: Read>
#   body: the SQL; answers {"meta": [...], "data": [{...}], "rows": n}
#
# Configuration comes from the environment or Rails credentials:
# CLOUDFLARE_ACCOUNT_ID / cloudflare.account_id,
# CLOUDFLARE_ANALYTICS_API_TOKEN / cloudflare.analytics_api_token and
# USAGE_DATASET / cloudflare.usage_dataset (data_api_requests by default;
# data_api_requests_staging on staging). The token is never logged.
class AnalyticsEngineClient
  class Error < StandardError; end
  class NotConfigured < Error; end

  ENDPOINT = "https://api.cloudflare.com/client/v4/accounts/%s/analytics_engine/sql".freeze
  DEFAULT_DATASET = "data_api_requests".freeze
  TIMEOUT = { connect_timeout: 3, operation_timeout: 20 }.freeze

  def self.setting(env_name, credential_key)
    ENV[env_name].presence || Rails.application.credentials.dig(:cloudflare, credential_key).presence
  end

  def self.configured? = new.configured?

  attr_reader :dataset

  def initialize(account_id: self.class.setting("CLOUDFLARE_ACCOUNT_ID", :account_id),
                 api_token: self.class.setting("CLOUDFLARE_ANALYTICS_API_TOKEN", :analytics_api_token),
                 dataset: self.class.setting("USAGE_DATASET", :usage_dataset) || DEFAULT_DATASET,
                 http: nil)
    @account_id = account_id.to_s
    @api_token = api_token.to_s
    @dataset = dataset.to_s
    @http = http
    raise ArgumentError, "invalid dataset name" unless @dataset.match?(/\A[a-z0-9_]+\z/)
  end

  def configured? = @account_id.present? && @api_token.present?

  # The rows of one SQL query, as hashes with string keys.
  def query(sql)
    raise NotConfigured, "Analytics Engine is not configured" unless configured?

    response = http.request("POST", format(ENDPOINT, ERB::Util.url_encode(@account_id)),
      headers: { "authorization" => "Bearer #{@api_token}", "content-type" => "text/plain" }, body: sql)
    raise Error, "Analytics Engine request failed: #{response.error.class}" unless response.respond_to?(:status)

    status = response.status.to_i
    raise Error, "Analytics Engine answered HTTP #{status}" unless status.between?(200, 299)

    body = JSON.parse(response.body.to_s)
    rows = body["data"]
    raise Error, "Analytics Engine answered without data" unless rows.is_a?(Array)

    rows
  rescue JSON::ParserError
    raise Error, "Analytics Engine answered invalid JSON"
  rescue HTTPX::Error, SocketError, SystemCallError, Timeout::Error, IOError => error
    raise Error, "Analytics Engine request failed: #{error.class}"
  end

  # A timestamp as an Analytics Engine SQL literal.
  def self.time(value) = "toDateTime('#{value.utc.strftime('%Y-%m-%d %H:%M:%S')}')"

  private

  def http = @http ||= HTTPX.with(timeout: TIMEOUT)
end
