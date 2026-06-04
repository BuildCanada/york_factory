module Localizable
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
  end

  private

  def switch_locale(&action)
    locale = params[:locale] || extract_locale_from_header || "en"
    locale = "en" unless %w[en fr].include?(locale)
    I18n.with_locale(locale.to_sym, &action)
  end

  def extract_locale_from_header
    accept_language = request.headers["Accept-Language"]
    return nil unless accept_language
    accept_language.scan(/^[a-z]{2}/).first
  end
end
