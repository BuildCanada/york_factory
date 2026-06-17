require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module YorkFactory
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])

    # Not api_only: Doorkeeper's provider UI (authorization screen, OAuth
    # application management) needs the full middleware stack — cookies, session,
    # flash and view rendering. The full stack provides these by default, so we
    # only configure the session cookie (shared across .buildcanada.com
    # subdomains in production for SSO).
    config.active_record.schema_format = :sql

    config.i18n.available_locales = %i[en fr]
    config.i18n.default_locale = :en

    config.session_store :cookie_store,
      key: "_york_factory_session",
      domain: (".buildcanada.com" if Rails.env.production?)
  end
end
