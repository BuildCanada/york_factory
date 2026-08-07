# PostHog analytics — posthog-rails wraps posthog-ruby and provides:
#   - Automatic exception capture for unhandled controller errors
#   - ActiveJob failure instrumentation
#   - Rails.error subscriber integration
#   - Automatic current_user context on error events
#
# Keys are read from the environment so the app boots safely with no
# PostHog config. In development, a missing token is logged loudly so
# events are never silently missed.

token = ENV.fetch("POSTHOG_PROJECT_TOKEN", nil)
host  = ENV.fetch("POSTHOG_HOST", "https://us.i.posthog.com")

if token.blank? && Rails.env.development?
  warn "[PostHog] POSTHOG_PROJECT_TOKEN variable required by PostHog is missing or " \
       "un-configured, this causes events to be silently missed. " \
       "This error stops appearing once POSTHOG_PROJECT_TOKEN is configured."
end

# Always initialize so PostHog.capture/identify calls are safe even without a
# token (posthog-ruby silently drops events when api_key is nil).
PostHog.init do |config|
  config.api_key = token
  config.host    = host
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
