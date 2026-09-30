# Discovery documents for OAuth 2.1 and MCP (docs/public-interface-design.md §4.6):
#
# - RFC 9728 protected resource metadata, served on data.buildcanada.com:
#     /.well-known/oauth-protected-resource        the MCP server (the root default)
#     /.well-known/oauth-protected-resource/mcp    the MCP server
#     /.well-known/oauth-protected-resource/v1     the REST API
# - RFC 8414 authorization server metadata, served on auth.buildcanada.com:
#     /.well-known/oauth-authorization-server
#
# The URLs come from Oauth::Settings; in development and test one host plays
# both roles.
class WellKnownController < ActionController::API
  CACHE_FOR = 1.hour

  def protected_resource
    kind = params[:resource_path].present? ? Oauth::Settings::RESOURCE_PATHS.key("/#{params[:resource_path]}") : :mcp
    return head(:not_found) unless kind

    cache_publicly
    render json: {
      resource: Oauth::Settings.resource(kind, request),
      authorization_servers: [ Oauth::Settings.issuer(request) ],
      scopes_supported: Oauth::Settings::SCOPES,
      bearer_methods_supported: %w[header],
      resource_name: kind == :mcp ? "Build Canada data (MCP server)" : "Build Canada data API",
      resource_documentation: "#{Oauth::Settings.data_origin(request)}/docs/#{kind == :mcp ? 'mcp' : 'api'}"
    }
  end

  def authorization_server
    issuer = Oauth::Settings.issuer(request)
    cache_publicly
    render json: {
      issuer:,
      authorization_endpoint: "#{issuer}/oauth/authorize",
      token_endpoint: "#{issuer}/oauth/token",
      registration_endpoint: "#{issuer}/oauth/register",
      revocation_endpoint: "#{issuer}/oauth/revoke",
      scopes_supported: Oauth::Settings::SCOPES,
      response_types_supported: %w[code],
      response_modes_supported: %w[query form_post],
      grant_types_supported: %w[authorization_code refresh_token],
      token_endpoint_auth_methods_supported: %w[none client_secret_basic client_secret_post],
      revocation_endpoint_auth_methods_supported: %w[none client_secret_basic client_secret_post],
      code_challenge_methods_supported: %w[S256],
      client_id_metadata_document_supported: true,
      authorization_response_iss_parameter_supported: true,
      service_documentation: "#{Oauth::Settings.data_origin(request)}/docs/mcp"
    }
  end

  private

  # CORS for browser-based clients is in config/initializers/cors.rb.
  def cache_publicly = expires_in(CACHE_FOR, public: true)
end
