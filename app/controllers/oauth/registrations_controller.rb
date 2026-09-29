module Oauth
  # RFC 7591 dynamic client registration: POST /oauth/register. Kept for MCP
  # clients that predate Client ID Metadata Documents; public clients only.
  # Rate-limited per IP and overall in config/initializers/rack_attack.rb.
  class RegistrationsController < ActionController::API
    def create
      metadata = parse_body
      result = ClientRegistration.call(metadata, context: client_context, ip: request.remote_ip)
      response.headers["Cache-Control"] = "no-store"

      if result.ok?
        render json: result.response, status: :created
      else
        render json: { error: result.error, error_description: result.error_description }, status: :bad_request
      end
    end

    private

    def parse_body
      return unless request.media_type == "application/json"

      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      nil
    end

    def client_context = AuditEvent::Context.client(request)
  end
end
