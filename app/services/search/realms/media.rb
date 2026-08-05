module Search
  module Realms
    class Media < Base
      CONTENT_TYPES = %w[article opinion editorial column live_blog other].freeze
      PUBLISHER_DOMAINS = %w[
        cbc.ca ctvnews.ca globalnews.ca financialpost.com nationalpost.com
        theglobeandmail.com ottawacitizen.com theprovince.com lapresse.ca
        thestar.com torontosun.com
      ].freeze
      RECORD_TYPES = %w[article].freeze
      FIELD_TYPES = {
        "content_type" => :string,
        "publisher_name" => :string,
        "publisher_domain" => :string,
        "authors" => :string_array,
        "section" => :string,
        "word_count" => :integer,
        "image_url" => :string,
        "favicon_url" => :string
      }.freeze
      REQUIRED_FIELDS = %w[content_type publisher_name publisher_domain word_count].freeze
      FILTER_FIELDS = {
        "content_type" => %w[eq in],
        "publisher_name" => %w[eq in],
        "publisher_domain" => %w[eq in],
        "authors" => %w[contains_any contains_all],
        "section" => %w[eq in],
        "word_count" => %w[eq gt gte lt lte]
      }.freeze
      FACET_FIELDS = %w[content_type publisher_name publisher_domain authors section].freeze
      TURBOPUFFER_SCHEMA = {
        content_type: { type: "string", filterable: true },
        publisher_name: { type: "string", filterable: true },
        publisher_domain: { type: "string", filterable: true },
        authors: { type: "[]string", filterable: true },
        section: { type: "string", filterable: true },
        word_count: { type: "uint", filterable: true },
        image_url: { type: "string", filterable: false },
        favicon_url: { type: "string", filterable: false }
      }.freeze

      class << self
        def validate_realm_data(data, _document)
          errors = []
          errors << "content_type is not supported" unless CONTENT_TYPES.include?(data["content_type"])
          errors << "publisher_domain is not supported" unless PUBLISHER_DOMAINS.include?(data["publisher_domain"])
          errors
        end
      end
    end
  end
end
