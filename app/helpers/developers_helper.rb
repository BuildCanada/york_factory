module DevelopersHelper
  KEY_STATUS_BADGES = { "active" => "badge-green", "rotating" => "badge-yellow", "suspended" => "badge-red", "revoked" => "badge-red", "expired" => "" }.freeze

  def key_status_badge(api_key)
    status = api_key.status
    label = status == "rotating" ? "Rotating until #{developer_time(api_key.grace_until)}" : status.capitalize
    tag.span(label, class: [ "badge", KEY_STATUS_BADGES[status] ])
  end

  def developer_time(time, fallback: "Never")
    time ? time.utc.strftime("%Y-%m-%d %H:%M UTC") : fallback
  end

  def plan_limit(value, unit)
    value ? "#{number_with_delimiter(value)} #{unit}" : "Unlimited"
  end

  def api_base_url = "https://data.buildcanada.com/v1"

  # The developer docs. data.buildcanada.com/ itself is kept for a future public site.
  def api_docs_url = "https://data.buildcanada.com/api"
end
