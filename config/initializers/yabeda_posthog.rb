# frozen_string_literal: true

# Export Rails, Active Record, and Active Job metrics to PostHog through the
# local Yabeda adapter. Metrics are production-only and intentionally contain
# no user or request identifiers; every attribute combination is a series.
if Rails.env.production?
  token = Rails.application.credentials.dig(:posthog, :api_key)

  if token.present?
    require Rails.root.join("lib/yabeda/post_hog")
    require "yabeda/rails"
    require "yabeda/activerecord"
    require "yabeda/activejob"

    Yabeda::PostHog.install!(
      api_key: token,
      host: Rails.application.credentials.dig(:posthog, :host).presence || "https://us.i.posthog.com",
      service_name: "york-factory",
      environment: Rails.env
    )

    Yabeda::ActiveJob.install!
  else
    warn "[PostHog] posthog.api_key credential is missing; metrics export is disabled."
  end
end
