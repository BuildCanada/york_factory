module Oauth
  # RFC 7591 dynamic client registration (POST /oauth/register), kept for MCP
  # clients that predate Client ID Metadata Documents (deprecated in MCP
  # 2026-07-28). Registers public clients only: no secret is issued, and the
  # client proves itself with PKCE. Rate limits are in config/initializers/rack_attack.rb,
  # and unused registrations are pruned by Oauth::PruneUnusedClientsJob.
  #
  #   result = Oauth::ClientRegistration.call(metadata_hash, context:, ip:)
  #   result.ok?         # => true
  #   result.response    # => the RFC 7591 §3.2.1 body
  #   result.error       # => "invalid_redirect_uri" / "invalid_client_metadata"
  class ClientRegistration
    Result = Data.define(:application, :error, :error_description) do
      def ok? = error.nil?

      def response
        app = application
        {
          client_id: app.uid,
          client_id_issued_at: app.created_at.to_i,
          client_name: app.name,
          redirect_uris: app.redirect_uris,
          grant_types: ClientMetadataDocument::GRANT_TYPES,
          response_types: %w[code],
          token_endpoint_auth_method: "none",
          scope: app.scopes.to_s,
          client_uri: app.client_uri,
          logo_uri: app.logo_url
        }.compact
      end
    end

    MAX_REDIRECT_URIS = 10
    APPLICATION_TYPES = %w[native web].freeze

    def self.call(metadata, **) = new(metadata, **).call

    def initialize(metadata, context:, ip: nil)
      @metadata = metadata.is_a?(Hash) ? metadata.stringify_keys : nil
      @context = context
      @ip = ip
    end

    def call
      return failure("invalid_client_metadata", "The body must be a JSON object.") unless @metadata

      redirect_uris = @metadata["redirect_uris"]
      unless redirect_uris.is_a?(Array) && redirect_uris.any? && redirect_uris.size <= MAX_REDIRECT_URIS && redirect_uris.all?(String)
        return failure("invalid_redirect_uri", "redirect_uris must list 1 to #{MAX_REDIRECT_URIS} URIs.")
      end
      redirect_uris.each do |uri|
        problem = RedirectUriPolicy.problem(uri)
        return failure("invalid_redirect_uri", "#{uri} #{problem}.") if problem
      end

      auth_method = @metadata.fetch("token_endpoint_auth_method", "none")
      unless auth_method == "none"
        return failure("invalid_client_metadata", "Only public clients are registered: token_endpoint_auth_method must be \"none\".")
      end

      grant_types = Array(@metadata.fetch("grant_types", ClientMetadataDocument::GRANT_TYPES))
      unless grant_types.include?("authorization_code") && (grant_types - ClientMetadataDocument::GRANT_TYPES).empty?
        return failure("invalid_client_metadata", "grant_types must include authorization_code and may add only refresh_token.")
      end
      unless Array(@metadata.fetch("response_types", %w[code])) == %w[code]
        return failure("invalid_client_metadata", "response_types may only be [\"code\"].")
      end
      if @metadata.key?("application_type") && !APPLICATION_TYPES.include?(@metadata["application_type"])
        return failure("invalid_client_metadata", "application_type must be \"native\" or \"web\".")
      end

      requested = @metadata["scope"].to_s.split
      unknown = requested - Settings::SCOPES
      return failure("invalid_client_metadata", "Unknown scopes: #{unknown.join(' ')}.") if unknown.any?

      name = @metadata["client_name"]
      name = nil unless name.is_a?(String) && name.strip.present?

      app = Doorkeeper::Application.new(
        name: (name&.strip || RedirectUriPolicy.host_label(redirect_uris.first) || "MCP client").first(ClientMetadataDocument::MAX_NAME_LENGTH),
        redirect_uri: redirect_uris.join("\n"),
        confidential: false,
        client_type: "dynamic",
        scopes: (requested.presence || Settings::SCOPES).join(" "),
        client_uri: https_url(@metadata["client_uri"]),
        logo_url: https_url(@metadata["logo_uri"]),
        registration_ip: @ip
      )

      app.transaction do
        app.save!
        AuditEvent.record!("oauth.client_registered", context: @context, subject: app,
          metadata: { client_id: app.uid, client_type: "dynamic", client_name: app.name, redirect_uris: app.redirect_uris })
      end
      Result.new(application: app, error: nil, error_description: nil)
    rescue ActiveRecord::RecordInvalid => error
      field = error.record.errors.include?(:redirect_uri) ? "invalid_redirect_uri" : "invalid_client_metadata"
      failure(field, error.record.errors.full_messages.to_sentence)
    end

    private

    def https_url(value)
      value if value.is_a?(String) && value.length <= RedirectUriPolicy::MAX_LENGTH && URI.parse(value).is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      nil
    end

    def failure(error, description) = Result.new(application: nil, error:, error_description: description)
  end
end
