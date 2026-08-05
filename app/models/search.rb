module Search
  class ConfigurationError < StandardError; end

  def self.table_name_prefix
    "search_"
  end

  def self.turbopuffer_namespace(name = ProviderConfig.document_namespace)
    turbopuffer_client.namespace(name)
  end

  def self.turbopuffer_client
    @turbopuffer_client ||= begin
      api_key = ProviderConfig.turbopuffer_api_key
      raise ConfigurationError, "Turbopuffer API key is not configured" if api_key.blank?

      Turbopuffer::Client.new(
        api_key: api_key,
        region: ProviderConfig.turbopuffer_region,
        timeout: 30,
        max_retries: 4,
        compression: true
      )
    end
  end

  def self.reset_turbopuffer_client!
    @turbopuffer_client = nil
  end
end
