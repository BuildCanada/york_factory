module Edge
  # Pushes key changes to the Worker's KeyDO so they take effect at the edge
  # at once (docs/public-interface-design.md §4.3, the WS-H contract):
  #
  #   PUT    {edge}/internal/keys/{digest}  body: ApiKey#lookup_payload
  #   DELETE {edge}/internal/keys/{digest}  on revoke or expiry
  #
  # Rails stays the source of truth: the Worker re-fetches
  # /internal/keys/lookup on a miss and caches for 5 minutes, so a failed
  # push is retried in the background rather than failing the change. With
  # no EDGE_URL configured (before the Worker exists, and in development and
  # test), pushes are skipped.
  class Push
    class Error < StandardError; end

    TIMEOUT = { connect_timeout: 2, operation_timeout: 3 }.freeze

    def self.key(api_key, **) = new(**).key(api_key)

    def self.account(account, **) = new(**).account(account)

    def self.configured? = Edge.url.present? && Edge.secret.present?

    def initialize(http: nil, url: Edge.url, secret: Edge.secret)
      @http = http
      @url = url.to_s.chomp("/")
      @secret = secret
    end

    # Pushes one key; enqueues a retry if the Worker can't be reached.
    def key(api_key)
      return false if @url.blank? || @secret.blank?

      deliver!(api_key)
      true
    rescue Error => error
      Rails.logger.warn("[Edge::Push] key #{api_key.id}: #{error.message}; retrying in the background")
      api_key.push_to_edge_later
      false
    end

    # Pushes every key of an account, e.g. after a plan change or suspension.
    def account(account)
      return false if @url.blank? || @secret.blank?

      account.api_keys.where(revoked_at: nil).find_each { |api_key| key(api_key) }
      true
    end

    # Raises Edge::Push::Error on failure. Used by the retry job.
    def deliver!(api_key)
      return if @url.blank? || @secret.blank?

      path = "/internal/keys/#{api_key.token_digest}"
      if api_key.usable? || api_key.status == "suspended"
        body = JSON.generate(api_key.lookup_payload)
        send_request("PUT", path, body)
      else
        send_request("DELETE", path, "")
      end
    end

    private

    def send_request(method, path, body)
      headers = Signature.headers(method:, path:, body:, secret: @secret).merge("content-type" => "application/json")
      response = http.request(method, "#{@url}#{path}", headers:, body:)
      raise Error, "#{method} failed: #{response.error.class}" unless response.respond_to?(:status)

      status = response.status.to_i
      raise Error, "#{method} returned HTTP #{status}" unless status.between?(200, 299) || (method == "DELETE" && status == 404)
    rescue HTTPX::Error, SocketError, SystemCallError, Timeout::Error, IOError => error
      raise Error, "#{method} failed: #{error.class}"
    end

    def http = @http ||= HTTPX.with(timeout: TIMEOUT)
  end
end
