require "base64"

# Bifrost's governance admin API (https://bifrost.svc.buildcanada.com), used
# only when a public API key is created, rotated or revoked, and by the
# nightly reconciliation. Bifrost is never on the request path: keys are
# verified by york_factory (docs/public-interface-design.md D5, §4.3).
#
# Authenticates with the admin basic auth described in
# applications/bifrost/README.md. Configuration comes from the environment
# (BIFROST_URL, BIFROST_ADMIN_USERNAME, BIFROST_ADMIN_PASSWORD) or Rails
# credentials (bifrost.url, bifrost.admin_username, bifrost.admin_password).
#
# Virtual key values are secrets, and Bifrost returns them in plaintext, so
# this client never logs request or response bodies and never puts them in
# error messages.
class BifrostClient
  class Error < StandardError; end
  # Bifrost is unreachable, timed out, or answered 408, 429 or 5xx.
  class Unavailable < Error; end
  # Bifrost answered another non-2xx status.
  class RequestFailed < Error
    attr_reader :status

    def initialize(message, status:)
      super(message)
      @status = status
    end
  end
  class InvalidResponse < Error; end
  class NotConfigured < Error; end

  # A virtual key as Bifrost returns it. #inspect leaves out the value.
  VirtualKey = Data.define(:id, :name, :value, :is_active, :attributes) do
    def self.from(hash)
      new(
        id: hash["id"].to_s,
        name: hash["name"].to_s,
        value: hash["value"],
        is_active: hash.fetch("is_active", true) != false,
        attributes: hash.except("value")
      )
    end

    def inspect = "#<BifrostClient::VirtualKey id=#{id.inspect} name=#{name.inspect} is_active=#{is_active}>"
    alias_method :to_s, :inspect
  end

  DEFAULT_TIMEOUT = { connect_timeout: 3, operation_timeout: 10 }.freeze

  def self.setting(env_name, *credential_path)
    ENV[env_name].presence || Rails.application.credentials.dig(:bifrost, *credential_path).presence
  end

  def self.configured? = setting("BIFROST_URL", :url).present?

  def initialize(base_url: self.class.setting("BIFROST_URL", :url),
                 username: self.class.setting("BIFROST_ADMIN_USERNAME", :admin_username),
                 password: self.class.setting("BIFROST_ADMIN_PASSWORD", :admin_password),
                 http: nil)
    @base_url = base_url.to_s.chomp("/")
    @username = username
    @password = password
    @http = http
  end

  # Creates a virtual key with no LLM providers (provider_configs: []), so it
  # opens nothing in Bifrost itself.
  def create_virtual_key(name:, description:, customer_id: nil, rate_limit: nil)
    body = {
      name:,
      description:,
      is_active: true,
      provider_configs: [],
      customer_id:,
      rate_limit:
    }.compact
    data = request(:post, "/api/governance/virtual-keys", body)
    key = VirtualKey.from(extract(data, "virtual_key"))
    raise InvalidResponse, "Bifrost returned a virtual key without an id or value" if key.id.blank? || key.value.blank?

    key
  end

  def get_virtual_key(id)
    data = request(:get, "/api/governance/virtual-keys/#{encode(id)}")
    VirtualKey.from(extract(data, "virtual_key"))
  end

  def list_virtual_keys
    data = request(:get, "/api/governance/virtual-keys")
    keys = data.is_a?(Hash) ? data["virtual_keys"] : nil
    raise InvalidResponse, "Bifrost returned an unexpected virtual key list" unless keys.is_a?(Array)

    keys.map { |hash| VirtualKey.from(hash) }
  end

  # Sets is_active: false. Per applications/bifrost/README.md, a PUT replaces
  # budgets and provider_configs wholesale, so the key is re-read first and
  # both are sent back unchanged. Returns false if the key is already gone.
  def deactivate_virtual_key(id)
    current = get_virtual_key(id)
    return true unless current.is_active

    request(:put, "/api/governance/virtual-keys/#{encode(id)}", {
      is_active: false,
      budgets: Array(current.attributes["budgets"]).map { |budget| budget.slice("id", "max_limit", "reset_duration", "reset_config").compact },
      provider_configs: Array(current.attributes["provider_configs"]).map { |config| provider_config_for_put(config) }
    })
    true
  rescue RequestFailed => error
    raise unless error.status == 404

    false
  end

  # One Bifrost customer per account, so a virtual key's owner is visible in
  # Bifrost's UI. Returns the customer id.
  def create_customer(name:)
    data = request(:post, "/api/governance/customers", { name: })
    customer = extract(data, "customer")
    id = customer["id"].to_s
    raise InvalidResponse, "Bifrost returned a customer without an id" if id.blank?

    id
  end

  private

  def request(method, path, body = nil)
    raise NotConfigured, "Bifrost is not configured (BIFROST_URL)" if @base_url.blank?

    options = { headers: headers }
    options[:body] = JSON.generate(body) if body
    response = http.request(method.to_s.upcase, "#{@base_url}#{path}", **options)

    raise Unavailable, "Bifrost #{method.upcase} #{path} failed: #{response.error.class}" unless response.respond_to?(:status)

    status = response.status.to_i
    raise Unavailable, "Bifrost #{method.upcase} #{path} returned HTTP #{status}" if status == 408 || status == 429 || status >= 500
    raise RequestFailed.new("Bifrost #{method.upcase} #{path} returned HTTP #{status}", status:) unless status.between?(200, 299)

    text = response.body.to_s
    text.empty? ? {} : JSON.parse(text)
  rescue JSON::ParserError
    raise InvalidResponse, "Bifrost #{method.upcase} #{path} returned invalid JSON"
  rescue HTTPX::Error, SocketError, SystemCallError, Timeout::Error, IOError => error
    raise Unavailable, "Bifrost #{method.upcase} #{path} failed: #{error.class}"
  end

  def extract(data, key)
    value = data.is_a?(Hash) ? (data[key] || data) : nil
    raise InvalidResponse, "Bifrost returned an unexpected #{key.tr('_', ' ')}" unless value.is_a?(Hash)

    value
  end

  def provider_config_for_put(config)
    entry = config.slice("id", "provider", "allowed_models", "weight", "budget", "rate_limit").compact
    key_ids = config["key_ids"].presence || Array(config["keys"]).filter_map { |key| key["key_id"] || key["id"] }.presence
    # Without key_ids Bifrost resets allow_all_keys (README, "Meta").
    entry.merge("key_ids" => key_ids || [ "*" ])
  end

  def headers
    {
      "authorization" => "Basic #{Base64.strict_encode64("#{@username}:#{@password}")}",
      "content-type" => "application/json",
      "accept" => "application/json"
    }
  end

  def encode(id) = ERB::Util.url_encode(id.to_s)

  def http = @http ||= HTTPX.with(timeout: DEFAULT_TIMEOUT)
end
