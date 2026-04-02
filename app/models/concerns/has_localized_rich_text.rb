module HasLocalizedRichText
  extend ActiveSupport::Concern

  class_methods do
    def has_localized_rich_text(name)
      I18n.available_locales.each do |locale|
        has_rich_text :"#{name}_#{locale}"
      end

      # Locale-aware getter with fallback to English
      define_method(name) do
        rt = public_send(:"#{name}_#{I18n.locale}")
        if rt.blank? && I18n.locale != :en
          rt = public_send(:"#{name}_en")
        end
        rt
      end

      # Locale-aware setter
      define_method(:"#{name}=") do |value|
        public_send(:"#{name}_#{I18n.locale}=", value)
      end
    end
  end
end
