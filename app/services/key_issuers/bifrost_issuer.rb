module KeyIssuers
  # Issues the secret as a Bifrost virtual key with no LLM providers
  # (docs/public-interface-design.md D5, §4.3 step 2). The virtual key is
  # named data-api:acct_<account>:key_<key>, which is how
  # Keys::ReconcileBifrostJob recognizes ours.
  class BifrostIssuer
    NAME_PREFIX = "data-api:".freeze
    VALUE_PREFIX = "sk-bf-".freeze

    def self.virtual_key_name(api_key) = "#{NAME_PREFIX}acct_#{api_key.account_id}:key_#{api_key.id}"

    # [account_id, key_id] from a data-api virtual key name, or nil.
    def self.parse_virtual_key_name(name)
      match = /\A#{Regexp.escape(NAME_PREFIX)}acct_(\d+):key_(\d+)\z/.match(name.to_s)
      match && [ match[1].to_i, match[2].to_i ]
    end

    def self.customers_enabled?
      setting = ENV["BIFROST_CUSTOMERS"].presence || Rails.application.credentials.dig(:bifrost, :customers)
      setting.nil? || ActiveModel::Type::Boolean.new.cast(setting)
    end

    def initialize(client: BifrostClient.new)
      @client = client
    end

    def name = "bifrost"

    def issue(api_key)
      account = api_key.account
      virtual_key = @client.create_virtual_key(
        name: self.class.virtual_key_name(api_key),
        description: "Build Canada data API key (no LLM access)",
        customer_id: customer_id_for(account),
        rate_limit: { request_max_limit: account.plan_definition.rate, request_reset_duration: "1m" }
      )
      unless virtual_key.value.start_with?(VALUE_PREFIX)
        deactivate_quietly(virtual_key.id)
        raise Unavailable, "Bifrost returned a virtual key value in an unexpected format"
      end

      Issued.new(secret: virtual_key.value.delete_prefix(VALUE_PREFIX), bifrost_vk_id: virtual_key.id)
    rescue BifrostClient::Error => error
      raise Unavailable, error.message
    end

    def deactivate(api_key)
      return true if api_key.bifrost_vk_id.blank?

      @client.deactivate_virtual_key(api_key.bifrost_vk_id)
    rescue BifrostClient::Error => error
      raise Unavailable, error.message
    end

    private

    def customer_id_for(account)
      return nil unless self.class.customers_enabled?
      return account.bifrost_customer_id if account.bifrost_customer_id.present?

      customer_id = @client.create_customer(name: "#{NAME_PREFIX}acct_#{account.id}")
      account.update_columns(bifrost_customer_id: customer_id, updated_at: Time.current)
      customer_id
    end

    def deactivate_quietly(id)
      @client.deactivate_virtual_key(id)
    rescue BifrostClient::Error
      nil # Keys::ReconcileBifrostJob deactivates orphans nightly.
    end
  end
end
