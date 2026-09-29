module Oauth
  # The authorization endpoint (GET/POST/DELETE /oauth/authorize), extending
  # Doorkeeper's for the MCP 2026-07-28 authorization spec
  # (docs/public-interface-design.md §4.6). First-party apps (TradingPost)
  # behave as before, apart from the `iss` parameter.
  #
  # For public-API clients (Client ID Metadata Documents, dynamic
  # registration):
  # - an https client_id is resolved as a Client ID Metadata Document;
  # - the redirect URI must match a registered one exactly;
  # - PKCE with S256 is required (Doorkeeper refuses `plain`);
  # - `resource` (RFC 8707) is required and must be one of the client's
  #   resources; it becomes the token's audience;
  # - the consent screen shows the client, its domain, where it redirects and
  #   the scopes in plain words, and asks which account usage is billed to;
  # - read:persons is granted only if that account accepted the data terms.
  #
  # Every authorization response carries `iss` (RFC 9207).
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    before_action :load_client_application, only: %i[new create destroy]
    before_action :check_public_api_request, only: %i[new create]

    helper_method :consent

    Consent = Data.define(:application, :resource_kind, :scopes, :accounts, :account, :persons_available) do
      def scope_rows
        scopes.map do |scope|
          available = scope != "read:persons" || persons_available
          { scope:, description: Settings::SCOPE_DESCRIPTIONS.fetch(scope, scope), available:,
            note: (Settings::PERSONS_NOTE if scope == "read:persons") }
        end
      end

      def resource_label = resource_kind == :mcp ? "the Build Canada MCP server" : "the Build Canada data API"
    end

    # Denying consent.
    def destroy
      super
      return unless public_api_client?

      AuditEvent.record!("oauth.denied", context: audit_context, account: chosen_account, subject: @client_application,
        metadata: { client_id: @client_application.uid, client_name: @client_application.name })
    end

    private

    # --- Client resolution --------------------------------------------------

    def load_client_application
      client_id = params[:client_id].to_s
      @client_application =
        if ClientMetadataDocument.url?(client_id)
          ClientMetadataDocument.resolve(client_id, context: audit_context)
        else
          Doorkeeper::Application.find_by(uid: client_id)
        end
    rescue ClientMetadataDocument::Invalid => error
      render_problem(error.message)
    end

    def public_api_client? = @client_application&.public_api? || false

    # --- Public-API request checks ------------------------------------------

    # Doorkeeper validates the client, redirect URI, scopes and PKCE. Then,
    # for public-API clients, the stricter checks below; an error that can
    # safely go back to the client is redirected there.
    def check_public_api_request
      return unless public_api_client?
      return unless pre_auth.authorizable?

      unless RedirectUriPolicy.matches_registered?(params[:redirect_uri].to_s, @client_application.redirect_uris)
        return render_problem("The redirect URI doesn't exactly match one registered for #{@client_application.name}.")
      end
      if pre_auth.code_challenge.blank?
        return redirect_with_error("invalid_request", "PKCE is required: send code_challenge with code_challenge_method=S256.")
      end
      if requested_resource.nil?
        return redirect_with_error("invalid_target", "Send resource=#{Settings.resource(:mcp, request)} (RFC 8707).")
      end
      unless @client_application.allowed_resource?(requested_resource, request)
        redirect_with_error("invalid_target", "#{params[:resource]} isn't a resource this client may use.")
      end
    end

    def requested_resource
      return @requested_resource if defined?(@requested_resource)

      canonical = Settings.canonical_resource(params[:resource])
      @requested_resource = canonical if canonical && Settings.resources(request).include?(canonical)
    end

    # --- Parameters handed to Doorkeeper ------------------------------------

    def pre_auth_params
      permitted = super
      return permitted.except(:resource, :account_id) unless public_api_client?

      permitted.merge(resource: requested_resource, account_id: chosen_account&.id, scope: granted_scope)
    end

    # Accounts the user may bill: their personal account, and organization
    # accounts where they manage keys.
    def billable_accounts
      @billable_accounts ||= begin
        personal = Account.personal_for!(current_resource_owner)
        others = current_resource_owner.accounts.where.not(id: personal.id).includes(:memberships).select { |account| account.manageable_by?(current_resource_owner) }
        [ personal, *others.sort_by(&:name) ]
      end
    end

    def chosen_account
      return @chosen_account if defined?(@chosen_account)

      @chosen_account = billable_accounts.find { |account| account.id.to_s == params[:account_id].to_s } || billable_accounts.first
    end

    def requested_scopes
      requested = params[:scope].to_s.split
      requested = Settings::DEFAULT_SCOPES if requested.empty?
      requested.uniq
    end

    # What the token gets: the requested scopes, minus read:persons if the
    # chosen account can't hold it. Unknown scopes are left in, so Doorkeeper
    # answers invalid_scope for them.
    def granted_scope
      scopes = requested_scopes
      scopes -= [ "read:persons" ] if chosen_account && !persons_available?(chosen_account)
      scopes = Settings::DEFAULT_SCOPES if scopes.empty?
      scopes.join(" ")
    end

    def persons_available?(account) = Keys::Policy.new(account, current_resource_owner).grantable?("read:persons")

    def consent
      @consent ||= Consent.new(
        application: @client_application,
        resource_kind: Settings::RESOURCE_PATHS.key(URI.parse(requested_resource.to_s).path),
        scopes: requested_scopes & Settings::SCOPES,
        accounts: billable_accounts,
        account: chosen_account,
        persons_available: persons_available?(chosen_account)
      )
    end

    # --- Responses ----------------------------------------------------------

    # RFC 9207: the issuer on every authorization response, success or error.
    def redirect_or_render(auth)
      return super unless auth.redirectable?

      if pre_auth.form_post_response?
        render :form_post, locals: { auth: IssuedResponse.new(auth.body.merge(iss: Settings.issuer(request))) }
      else
        redirect_to with_iss(auth.redirect_uri), allow_other_host: true
      end
    end

    IssuedResponse = Data.define(:body)

    def with_iss(uri)
      parsed = URI.parse(uri)
      return uri if parsed.fragment.present? # implicit-style fragment responses aren't offered

      query = URI.decode_www_form(parsed.query.to_s).reject { |key, _| key == "iss" }
      # RFC 7636 §4.4.1: an unsupported PKCE method (plain) is invalid_request.
      query = query.map { |key, value| key == "error" && value == "invalid_code_challenge_method" ? [ key, "invalid_request" ] : [ key, value ] }
      parsed.query = URI.encode_www_form(query + [ [ "iss", Settings.issuer(request) ] ])
      parsed.to_s
    rescue URI::InvalidURIError
      uri
    end

    def redirect_with_error(error, description)
      query = { error:, error_description: description, state: params[:state].presence, iss: Settings.issuer(request) }.compact
      separator = params[:redirect_uri].to_s.include?("?") ? "&" : "?"
      redirect_to "#{params[:redirect_uri]}#{separator}#{query.to_query}", allow_other_host: true
    end

    def render_problem(message)
      @problem = message
      render :problem, status: :bad_request
    end

    # --- Audit ----------------------------------------------------------------

    def after_successful_authorization(context)
      super
      grant = context.auth.try(:issued_token)
      return unless public_api_client? && grant.respond_to?(:resource) && grant.resource.present?

      AuditEvent.record!("oauth.authorized", context: audit_context, account: chosen_account, subject: @client_application,
        metadata: { client_id: @client_application.uid, client_name: @client_application.name, scopes: grant.scopes.to_a,
                    resource: grant.resource, redirect_uri: grant.redirect_uri })
    end

    def audit_context = AuditEvent::Context.from_request(request, actor: current_resource_owner)
  end
end
