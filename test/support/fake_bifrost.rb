# An in-memory stand-in for Bifrost's governance admin API, injected into
# BifrostClient as its HTTP transport. Tests never call a real Bifrost.
class FakeBifrost
  Response = Data.define(:status, :body)
  ErrorResponse = Data.define(:error)

  attr_reader :requests, :virtual_keys, :customers

  def initialize
    @requests = []
    @virtual_keys = {}
    @customers = {}
    @down = false
    @next_id = 0
  end

  def down! = @down = true

  def up! = @down = false

  def client = BifrostClient.new(base_url: "https://bifrost.test", username: "admin", password: "admin-password", http: self)

  def issuer = KeyIssuers::BifrostIssuer.new(client:)

  # Adds a virtual key as if created elsewhere (e.g. an orphan).
  def add_virtual_key(name:, is_active: true, provider_configs: [], budgets: [])
    id = next_id("vk")
    @virtual_keys[id] = { "id" => id, "name" => name, "value" => "sk-bf-#{SecureRandom.uuid}", "is_active" => is_active,
                          "provider_configs" => provider_configs, "budgets" => budgets }
  end

  def request(method, url, headers: {}, body: nil)
    json = body ? JSON.parse(body) : nil
    @requests << { method:, url:, headers:, json: }
    return ErrorResponse.new(error: Errno::ECONNREFUSED.new("bifrost.test")) if @down

    path = URI.parse(url).path
    case [ method, path ]
    in [ "POST", "/api/governance/virtual-keys" ]
      id = next_id("vk")
      @virtual_keys[id] = json.merge("id" => id, "value" => "sk-bf-#{SecureRandom.uuid}", "budgets" => [])
      respond(200, { "message" => "Virtual key created successfully", "virtual_key" => @virtual_keys[id] })
    in [ "GET", "/api/governance/virtual-keys" ]
      respond(200, { "virtual_keys" => @virtual_keys.values, "count" => @virtual_keys.size })
    in [ "GET", %r{\A/api/governance/virtual-keys/(?<id>[^/]+)\z} ]
      vk = @virtual_keys[Regexp.last_match[:id]]
      vk ? respond(200, { "virtual_key" => vk }) : respond(404, { "error" => "not found" })
    in [ "PUT", %r{\A/api/governance/virtual-keys/(?<id>[^/]+)\z} ]
      vk = @virtual_keys[Regexp.last_match[:id]]
      return respond(404, { "error" => "not found" }) unless vk

      vk.merge!(json)
      respond(200, { "virtual_key" => vk })
    in [ "POST", "/api/governance/customers" ]
      id = next_id("cust")
      @customers[id] = json.merge("id" => id)
      respond(200, { "customer" => @customers[id] })
    else
      respond(404, { "error" => "no route" })
    end
  end

  def requests_to(method, path_pattern) = @requests.select { |r| r[:method] == method && URI.parse(r[:url]).path.match?(path_pattern) }

  private

  def respond(status, payload) = Response.new(status:, body: JSON.generate(payload))

  def next_id(prefix) = "#{prefix}-#{@next_id += 1}"
end
