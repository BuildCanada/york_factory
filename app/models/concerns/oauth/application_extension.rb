module Oauth
  # Public-API behaviour for Doorkeeper::Application (included from
  # config/initializers/doorkeeper.rb). docs/public-interface-design.md §4.6.
  #
  # client_type says how an application came to exist:
  #   first_party        created by staff in /oauth/applications (TradingPost).
  #                      Unchanged: no resource indicator, 2-hour tokens.
  #   registered         registered by a user in the developer console (reserved).
  #   dynamic            RFC 7591 dynamic client registration (POST /oauth/register).
  #   metadata_document  a Client ID Metadata Document: uid is the document's URL.
  # Every type but first_party is a public-API client: its tokens are bound to
  # one resource, last an hour, and belong to an account.
  module ApplicationExtension
    extend ActiveSupport::Concern

    CLIENT_TYPES = %w[first_party registered dynamic metadata_document].freeze

    included do
      belongs_to :account, optional: true

      validates :client_type, inclusion: { in: CLIENT_TYPES }

      scope :public_api, -> { where.not(client_type: "first_party") }
    end

    def public_api? = client_type != "first_party"

    def metadata_document? = client_type == "metadata_document"

    def dynamic? = client_type == "dynamic"

    def disabled? = disabled_at.present?

    def reviewed? = reviewed_at.present?

    def redirect_uris = redirect_uri.to_s.split

    # The resources this client may ask for. Empty means every public resource.
    def allowed_resource?(resource, request = nil)
      allowed = resource_uris.presence || Oauth::Settings.resources(request)
      allowed.include?(resource)
    end

    # The host a person should recognise on the consent screen: the CIMD URL's
    # host, else the client's home page, else its first redirect URI.
    def display_host
      [ (uid if metadata_document?), client_uri, redirect_uris.first ].compact.each do |candidate|
        host = URI.parse(candidate).host
        return host if host.present?
      rescue URI::InvalidURIError
        next
      end
      nil
    end

    def redirect_hosts = redirect_uris.filter_map { |uri| Oauth::RedirectUriPolicy.host_label(uri) }.uniq

    # Every redirect URI is on this machine (localhost or a loopback IP), so
    # anything running locally could claim to be this client.
    def local_redirects_only? = redirect_uris.any? && redirect_uris.all? { |uri| Oauth::RedirectUriPolicy.loopback?(uri) }

    def client_type_label
      { "first_party" => "Build Canada", "registered" => "Registered app", "dynamic" => "Dynamically registered",
        "metadata_document" => "Client ID Metadata Document" }.fetch(client_type, client_type)
    end
  end
end
