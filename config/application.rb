require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module YorkFactory
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])

    config.api_only = true
    config.active_record.schema_format = :sql

    config.i18n.available_locales = %i[en fr]
    config.i18n.default_locale = :en

    config.middleware.use Rack::MethodOverride
    config.middleware.use ActionDispatch::Cookies
    session_options = { key: "_york_factory_session" }
    session_options[:domain] = ".buildcanada.com" if Rails.env.production?
    config.middleware.use ActionDispatch::Session::CookieStore, **session_options
    config.middleware.use ActionDispatch::Flash
  end
end
