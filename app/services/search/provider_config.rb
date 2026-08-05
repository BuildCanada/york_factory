module Search
  module ProviderConfig
    module_function

    DEFAULT_COHERE_MODEL = "embed-v-4-0"
    DEFAULT_EMBEDDING_DIMENSIONS = 1_024
    DEFAULT_COHERE_MAX_INPUT_CHARACTERS = 400_000
    DEFAULT_TURBOPUFFER_REGION = "gcp-northamerica-northeast2"
    DEFAULT_DEFUDDLER_URL = "https://deffudler.svc.canadasbuilding.com"

    def cohere_endpoint
      setting("AZURE_COHERE_ENDPOINT", :azure_cohere, :endpoint)
    end

    def cohere_api_key
      setting("AZURE_COHERE_API_KEY", :azure_cohere, :api_key)
    end

    def cohere_model
      setting("AZURE_COHERE_MODEL", :azure_cohere, :model) || DEFAULT_COHERE_MODEL
    end

    def cohere_max_input_characters
      Integer(setting("AZURE_COHERE_MAX_INPUT_CHARACTERS", :azure_cohere, :max_input_characters) ||
        DEFAULT_COHERE_MAX_INPUT_CHARACTERS)
    rescue ArgumentError
      raise ArgumentError, "Azure Cohere max_input_characters must be an integer"
    end

    def turbopuffer_api_key
      setting("TURBOPUFFER_API_KEY", :turbopuffer, :api_key)
    end

    def turbopuffer_region
      setting("TURBOPUFFER_REGION", :turbopuffer, :region) || DEFAULT_TURBOPUFFER_REGION
    end

    def document_namespace
      setting("TURBOPUFFER_DOCUMENT_NAMESPACE", :turbopuffer, :namespace) ||
        "yf-#{Rails.env}-documents-v1"
    end

    def defuddler_api_key
      setting("DEFUDDLER_API_KEY", :defuddler, :api_key)
    end

    def defuddler_base_url
      setting("DEFUDDLER_BASE_URL", :defuddler, :base_url) || DEFAULT_DEFUDDLER_URL
    end

    def setting(environment_key, section, key)
      ENV[environment_key].presence || Rails.application.credentials.dig(:search, section, key)
    end
    private_class_method :setting
  end
end
