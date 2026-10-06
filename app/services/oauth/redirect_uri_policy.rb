require "ipaddr"

module Oauth
  # Which redirect URIs a public-API client may register, by dynamic
  # registration or in a Client ID Metadata Document. MCP 2026-07-28
  # "Communication Security": every redirect URI is either on localhost or
  # uses HTTPS. Native apps may also use a private-use URI scheme
  # (RFC 8252 §7.1), such as cursor:// or vscode://.
  #
  # Redirect URIs are then matched exactly at authorization (loopback IPs may
  # use any port, RFC 8252 §7.3).
  module RedirectUriPolicy
    MAX_LENGTH = 2_000
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1] ::1].freeze
    # Schemes that must never receive an authorization code.
    FORBIDDEN_SCHEMES = %w[javascript data file vbscript about blob ftp ws wss http https].freeze
    SCHEME_FORMAT = /\A[a-z][a-z0-9+.-]*\z/

    module_function

    # nil when the URI is acceptable, else the reason it isn't.
    def problem(value)
      string = value.to_s
      return "must be a string of at most #{MAX_LENGTH} characters" if string.empty? || string.length > MAX_LENGTH

      uri = URI.parse(string)
      return "must not have a fragment" if uri.fragment
      return "must be an absolute URI" if uri.scheme.blank?

      scheme = uri.scheme.downcase
      case scheme
      when "https"
        return "must have a host" if uri.host.blank?
        return "must not contain user info" if uri.userinfo
      when "http"
        return "must use https unless it is on localhost" unless loopback?(string)
      else
        return "uses a scheme that isn't allowed" if FORBIDDEN_SCHEMES.include?(scheme) || !scheme.match?(SCHEME_FORMAT)
      end
      nil
    rescue URI::InvalidURIError
      "isn't a valid URI"
    end

    def valid?(value) = problem(value).nil?

    def loopback?(value)
      uri = URI.parse(value.to_s)
      uri.is_a?(URI::HTTP) && loopback_host?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def loopback_host?(host)
      return false if host.blank?
      return true if LOOPBACK_HOSTS.include?(host.downcase)

      IPAddr.new(host.delete_prefix("[").delete_suffix("]")).loopback?
    rescue IPAddr::Error
      false
    end

    # Exact matching (OAuth 2.1 §2.3.1): the presented URI must equal a
    # registered one, except that a loopback IP's port may differ.
    def matches_registered?(presented, registered)
      registered.any? do |candidate|
        next true if presented == candidate
        next false unless loopback?(presented) && loopback?(candidate)

        a = URI.parse(presented)
        b = URI.parse(candidate)
        IPAddr.new(a.host.delete_prefix("[").delete_suffix("]")).loopback? &&
          [ a.scheme, a.host, a.path, a.query ] == [ b.scheme, b.host, b.path, b.query ]
      rescue URI::InvalidURIError, IPAddr::Error
        false
      end
    end

    # What the consent screen shows for a redirect URI: its host, or its
    # scheme for a private-use scheme.
    def host_label(value)
      uri = URI.parse(value.to_s)
      uri.host.presence || "#{uri.scheme}://"
    rescue URI::InvalidURIError
      nil
    end
  end
end
