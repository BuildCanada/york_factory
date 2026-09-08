# PostHog analytics — posthog-rails wraps posthog-ruby and provides:
#   - Automatic exception capture for unhandled controller errors
#   - ActiveJob failure instrumentation
#   - Rails.error subscriber integration
#   - Automatic current_user context on error events
#
# The project key is stored in encrypted Rails credentials, so Kamal needs
# only RAILS_MASTER_KEY to make it available in every deploy environment.

if Rails.env.production?
  PostHog.init do |config|
    config.api_key = Rails.application.credentials.dig(:posthog, :api_key)
    config.host = Rails.application.credentials.dig(:posthog, :host).presence || "https://us.i.posthog.com"
  end
else
  # Keep direct PostHog.capture/identify calls safe while guaranteeing that
  # development, test, console, and local runner activity never leaves the app.
  PostHog.init(api_key: nil, silence_disabled_client_error: true)
end

PostHog::Rails.configure do |config|
  # Auto-capture unhandled exceptions in controllers
  config.auto_capture_exceptions = true

  # Also capture exceptions that Rails rescues (e.g. ActiveRecord::RecordNotFound)
  config.report_rescued_exceptions = true

  # Auto-instrument ActiveJob failures
  config.auto_instrument_active_job = true

  # Attach the current user to every captured exception
  config.capture_user_context    = true
  config.current_user_method     = :current_user
  config.user_id_method          = :posthog_distinct_id

  # Forward Rails.logger output only from production. The OpenTelemetry gems
  # above are loaded lazily by posthog-rails when this is enabled.
  config.logs_enabled = Rails.env.production?
  config.logs_level = :info

  # Preserve useful production logs without exporting common PII or secrets.
  config.logs_before_send = proc do |record|
    record[:body] = record[:body]
      .to_s
      .gsub(/\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b/, "[FILTERED]")
      .gsub(/\b(Bearer|Token)\s+[\w.~+\/=:-]+/i, "\\1 [FILTERED]")
      .gsub(/([\"']?(?:password|secret|token|api[_-]?key|authorization|otp)[\"']?\s*(?:=>|:|=)\s*[\"'])[^\"']*([\"'])/i, "\\1[FILTERED]\\2")
    record
  end
end
