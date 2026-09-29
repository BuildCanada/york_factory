# Where a key's secret comes from (docs/public-interface-design.md §4.3).
# BifrostIssuer makes Bifrost the issuer of record; LocalIssuer generates the
# secret here, in the same format. The configured issuer (API_KEY_ISSUER or
# credentials api_keys.issuer) defaults to bifrost in production and local
# elsewhere, so development and test never call Bifrost.
module KeyIssuers
  Issued = Data.define(:secret, :bifrost_vk_id) do
    def inspect = "#<KeyIssuers::Issued bifrost_vk_id=#{bifrost_vk_id.inspect}>"
    alias_method :to_s, :inspect
  end

  # The issuer can't issue or deactivate right now. Nothing was stored.
  class Unavailable < StandardError; end

  def self.default_name
    ENV["API_KEY_ISSUER"].presence ||
      Rails.application.credentials.dig(:api_keys, :issuer).presence ||
      (Rails.env.production? ? "bifrost" : "local")
  end

  def self.default = self.for(default_name)

  def self.for(name)
    case name.to_s
    when "bifrost" then BifrostIssuer.new
    when "local" then LocalIssuer.new
    else raise ArgumentError, "Unknown key issuer #{name.inspect}"
    end
  end
end
