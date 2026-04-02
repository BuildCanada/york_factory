module Localizable
  extend ActiveSupport::Concern

  included do
    before_action :set_locale
  end

  private

  def set_locale
    locale = params[:locale] || extract_locale_from_header || "en"
    locale = "en" unless %w[en fr].include?(locale)
    I18n.locale = locale.to_sym
  end

  def extract_locale_from_header
    accept_language = request.headers["Accept-Language"]
    return nil unless accept_language
    accept_language.scan(/^[a-z]{2}/).first
  end
end
