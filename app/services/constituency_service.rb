# frozen_string_literal: true

require "http"

class ConstituencyService
  USER_AGENT = "BuildCanadaBot"

  PROVINCES = [
    "Alberta",
    "British Columbia",
    "Manitoba",
    "New Brunswick",
    "Newfoundland and Labrador",
    "Nova Scotia",
    "Ontario",
    "Prince Edward Island",
    "Québec",
    "Quebec",
    "Saskatchewan",
    "Yukon",
    "Northwest Territories",
    "Nunavut"
  ]

  PROV_ABBREVIATION_MAPPING = {
    "AB" => "Alberta",
    "BC" => "British Columbia",
    "MB" => "Manitoba",
    "NB" => "New Brunswick",
    "NL" => "Newfoundland and Labrador",
    "NS" => "Nova Scotia",
    "ON" => "Ontario",
    "PE" => "Prince Edward Island",
    "QC" => "Quebec",
    "SK" => "Saskatchewan",
    "YT" => "Yukon",
    "NT" => "Northwest Territories",
    "NU" => "Nunavut"
  }

  class << self
    def fetch_constituencies(postal_code)
      return nil if postal_code.blank?
      # Make the initial POST request
      url =  "https://represent.opennorth.ca/postcodes/#{postal_code.sub(/\s+/, "").upcase}/?format=json"

      response = HTTP.timeout(10)
                     .headers(
                       "User-Agent" => USER_AGENT,
                     )
                     .get(url)

      JSON.parse(response.body.to_s)
    rescue StandardError => e
      Rails.logger.error "Failed to fetch federal constituency: #{e.message}"
      nil
    end

  def format(constituencies)
    provincial_constituency = constituencies["representatives_centroid"].filter { |rep| PROVINCES.any? { |province| rep["representative_set_name"].include?(province) } }.first&.[]("district_name")

    {
      city: constituencies["city"].titleize,
      province: PROV_ABBREVIATION_MAPPING[constituencies["province"]],
      province_code: constituencies["province"],
      country_code: "CA",
      country: "Canada",
      longitude: constituencies["centroid"]["coordinates"][0],
      latitude: constituencies["centroid"]["coordinates"][1],
      federal_constituency: constituencies["representatives_centroid"].filter { |constituency| constituency["representative_set_name"] == "House of Commons" }.first&.[]("district_name"),
      provincial_constituency: provincial_constituency
    }
  end

  def federal_constituency(data)
    data["constituencies"].map do |constituency|
      {
        id: constituency["id"],
        name: constituency["name"],
        type: constituency["type"]
      }
    end
  end
  end
end
