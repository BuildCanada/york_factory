require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module YorkFactory
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])

    config.api_only = true

    config.i18n.available_locales = %i[en fr]
    config.i18n.default_locale = :en

    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_york_factory_session"
    config.middleware.use ActionDispatch::Flash
  end
end
