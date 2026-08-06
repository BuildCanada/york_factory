module Warehouse::Spending::Geography
  PROVINCES = {
    "AB" => "Alberta",
    "BC" => "British Columbia",
    "MB" => "Manitoba",
    "NB" => "New Brunswick",
    "NL" => "Newfoundland and Labrador",
    "NS" => "Nova Scotia",
    "NT" => "Northwest Territories",
    "NU" => "Nunavut",
    "ON" => "Ontario",
    "PE" => "Prince Edward Island",
    "QC" => "Quebec",
    "SK" => "Saskatchewan",
    "YT" => "Yukon"
  }.freeze
  PROVINCE_CODES = PROVINCES.invert.transform_keys(&:downcase).freeze

  module_function

  def province_name(code)
    PROVINCES[code.to_s.upcase] || code.to_s
  end

  def province_code(value)
    PROVINCE_CODES[value.to_s.downcase] || value.to_s.upcase
  end

  def country_name(code)
    TZInfo::Country.get(code.to_s.upcase).name
  rescue TZInfo::InvalidCountryCode
    code.to_s
  end

  def country_code(value)
    text = value.to_s
    return text.upcase if text.match?(/\A[A-Za-z]{2}\z/)

    country_codes_by_name[text.downcase] || text
  end

  def matching_province_codes(text)
    matching_codes(PROVINCES, text)
  end

  def matching_country_codes(text)
    matching_codes(countries, text)
  end

  def countries
    @countries ||= TZInfo::Country.all.to_h { |country| [ country.code, country.name ] }.freeze
  end

  def country_codes_by_name
    @country_codes_by_name ||= countries.invert.transform_keys(&:downcase).freeze
  end

  def matching_codes(mapping, text)
    needle = text.to_s.downcase
    mapping.filter_map { |code, name| code if name.downcase.include?(needle) }
  end
  private_class_method :matching_codes
end
