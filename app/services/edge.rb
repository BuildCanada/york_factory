# The data-edge Worker in front of data.buildcanada.com
# (docs/public-interface-design.md §5.5). Rails pushes key changes to it and
# answers its key lookups; both directions are HMAC-signed (Edge::Signature).
module Edge
  def self.setting(env_name, credential_key)
    ENV[env_name].presence || Rails.application.credentials.dig(:edge, credential_key).presence
  end

  def self.url = setting("EDGE_URL", :url)

  def self.secret = setting("EDGE_HMAC_SECRET", :hmac_secret)
end
