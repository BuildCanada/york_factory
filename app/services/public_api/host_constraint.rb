module PublicApi
  # Which hosts serve /v1. In production the public data API answers only on
  # data.buildcanada.com and data.staging.buildcanada.com (and whatever
  # PUBLIC_API_HOSTS lists instead), so /v1 on api.buildcanada.com or
  # auth.buildcanada.com is not a second copy of the API. Elsewhere any host
  # does, unless PUBLIC_API_HOSTS is set.
  module HostConstraint
    PRODUCTION_HOSTS = %w[data.buildcanada.com data.staging.buildcanada.com].freeze

    module_function

    def matches?(request)
      hosts.nil? || hosts.include?(request.host)
    end

    def hosts
      configured = ENV["PUBLIC_API_HOSTS"].to_s.split(",").map(&:strip).compact_blank
      return configured if configured.any?

      Rails.env.production? ? PRODUCTION_HOSTS : nil
    end
  end
end
