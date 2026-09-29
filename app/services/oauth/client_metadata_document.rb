module Oauth
  # OAuth Client ID Metadata Documents (draft-ietf-oauth-client-id-metadata-document-00),
  # the preferred way for MCP clients to register under MCP 2026-07-28. The
  # client_id is an HTTPS URL; the document at that URL describes the client.
  #
  #   app = Oauth::ClientMetadataDocument.resolve("https://claude.ai/oauth/mcp-client-metadata.json", context:)
  #
  # The document is fetched through Oauth::SafeFetch, validated, and upserted
  # as a public Doorkeeper application (client_type metadata_document) whose
  # uid is the URL, so the rest of Doorkeeper treats it like any other client.
  # It is cached for its Cache-Control max-age, clamped to 5 minutes to 24
  # hours. A failed fetch is not retried for a minute, and a client whose
  # document has become unreachable keeps working from the stored copy for up
  # to 7 days.
  class ClientMetadataDocument
    # The message is shown to the person on the error page.
    class Invalid < StandardError; end

    MIN_TTL = 5.minutes
    MAX_TTL = 24.hours
    STALE_GRACE = 7.days
    FAILURE_BACKOFF = 1.minute
    MAX_NAME_LENGTH = 100
    MAX_REDIRECT_URIS = 20
    GRANT_TYPES = %w[authorization_code refresh_token].freeze

    # A client_id that names a metadata document: an https URL with a path,
    # no fragment and no user info (CIMD draft §3).
    def self.url?(client_id)
      uri = URI.parse(client_id.to_s)
      uri.is_a?(URI::HTTPS) && uri.host.present? && uri.path.present? && uri.path != "/" &&
        uri.fragment.nil? && uri.userinfo.nil? && !uri.path.split("/").intersect?(%w[. ..])
    rescue URI::InvalidURIError
      false
    end

    def self.resolve(client_id, context:, now: Time.current) = new(client_id, context:, now:).resolve

    def initialize(client_id, context:, now: Time.current)
      @client_id = client_id.to_s
      @context = context
      @now = now
    end

    def resolve
      raise Invalid, "The client ID isn't a valid metadata document URL." unless self.class.url?(@client_id)

      app = Doorkeeper::Application.find_by(uid: @client_id)
      return app if app&.metadata_expires_at&.after?(@now)

      if recently_failed?
        return app if usable_stale?(app)

        raise Invalid, "The client's metadata document couldn't be loaded. Try again in a minute."
      end

      document, ttl = fetch
      upsert(app, document, ttl)
    rescue SafeFetch::Error => error
      remember_failure
      return app if usable_stale?(app)

      raise Invalid, "The client's metadata document #{error.message}."
    end

    private

    def fetch
      response = SafeFetch.get(@client_id)
      raise Invalid, "The client's metadata document returned HTTP #{response.status}." unless response.status == 200

      document = JSON.parse(response.body)
      raise Invalid, "The client's metadata document isn't a JSON object." unless document.is_a?(Hash)

      [ validate!(document), ttl_from(response.headers["cache-control"]) ]
    rescue JSON::ParserError
      remember_failure
      raise Invalid, "The client's metadata document isn't valid JSON."
    rescue Invalid
      remember_failure
      raise
    end

    def validate!(document)
      unless document["client_id"] == @client_id
        raise Invalid, "The client's metadata document names a different client_id than its URL."
      end

      name = document["client_name"]
      raise Invalid, "The client's metadata document has no client_name." unless name.is_a?(String) && name.strip.present?

      redirect_uris = document["redirect_uris"]
      unless redirect_uris.is_a?(Array) && redirect_uris.any? && redirect_uris.size <= MAX_REDIRECT_URIS && redirect_uris.all?(String)
        raise Invalid, "The client's metadata document needs 1 to #{MAX_REDIRECT_URIS} redirect_uris."
      end
      redirect_uris.each do |uri|
        problem = RedirectUriPolicy.problem(uri)
        raise Invalid, "The redirect URI #{uri.inspect} #{problem}." if problem
      end

      # Only public clients: a document is public, so it can't carry a
      # secret, and private_key_jwt isn't supported yet.
      if document.key?("client_secret") || document.key?("client_secret_expires_at")
        raise Invalid, "The client's metadata document must not contain a client secret."
      end
      auth_method = document.fetch("token_endpoint_auth_method", "none")
      raise Invalid, "Only public clients (token_endpoint_auth_method \"none\") are supported." unless auth_method == "none"

      grant_types = Array(document.fetch("grant_types", %w[authorization_code]))
      unless grant_types.include?("authorization_code") && (grant_types - GRANT_TYPES).empty?
        raise Invalid, "The client's grant_types must include authorization_code, and may add only refresh_token."
      end
      response_types = Array(document.fetch("response_types", %w[code]))
      raise Invalid, "The client's response_types may only be [\"code\"]." unless response_types == %w[code]

      {
        name: name.strip.first(MAX_NAME_LENGTH),
        redirect_uris:,
        client_uri: https_url(document["client_uri"]),
        logo_url: https_url(document["logo_uri"])
      }
    end

    def upsert(app, document, ttl)
      created = app.nil?
      app ||= Doorkeeper::Application.new(uid: @client_id, client_type: "metadata_document", confidential: false, metadata_url: @client_id)
      app.assign_attributes(
        name: document[:name],
        redirect_uri: document[:redirect_uris].join("\n"),
        client_uri: document[:client_uri],
        logo_url: document[:logo_url],
        scopes: Settings::SCOPES.join(" "),
        metadata_fetched_at: @now,
        metadata_expires_at: @now + ttl
      )
      changed = app.changed - %w[metadata_fetched_at metadata_expires_at updated_at]

      app.transaction do
        app.save!
        if created
          AuditEvent.record!("oauth.client_registered", context: @context, subject: app,
            metadata: { client_id: @client_id, client_type: "metadata_document", client_name: app.name, redirect_uris: app.redirect_uris })
        elsif changed.any?
          AuditEvent.record!("oauth.client_updated", context: @context, subject: app,
            metadata: { client_id: @client_id, changed: })
        end
      end
      app
    rescue ActiveRecord::RecordNotUnique
      Doorkeeper::Application.find_by!(uid: @client_id)
    rescue ActiveRecord::RecordInvalid => error
      raise Invalid, "The client's metadata document was rejected: #{error.record.errors.full_messages.to_sentence}."
    end

    def ttl_from(cache_control)
      return MIN_TTL if cache_control.to_s.match?(/no-store|no-cache/i)

      max_age = cache_control.to_s[/max-age=(\d+)/i, 1]
      max_age ? max_age.to_i.seconds.clamp(MIN_TTL, MAX_TTL) : MAX_TTL
    end

    def https_url(value)
      value if value.is_a?(String) && value.length <= RedirectUriPolicy::MAX_LENGTH && URI.parse(value).is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      nil
    end

    def usable_stale?(app) = app&.metadata_expires_at.present? && app.metadata_expires_at + STALE_GRACE > @now

    def failure_key = "oauth:cimd:failed:#{Digest::SHA256.hexdigest(@client_id)}"

    def recently_failed? = Rails.cache.exist?(failure_key)

    def remember_failure = Rails.cache.write(failure_key, true, expires_in: FAILURE_BACKOFF)
  end
end
