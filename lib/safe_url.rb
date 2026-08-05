require "digest"
require "ipaddr"
require "resolv"
require "uri"

module SafeUrl
  class Invalid < StandardError; end

  TRACKING_PARAMETERS = %w[
    fbclid gclid mc_cid mc_eid ref source
    utm_campaign utm_content utm_medium utm_source utm_term
  ].freeze

  BLOCKED_NETWORKS = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8
    169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
    192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24
    224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 ::ffff:0:0/96
    2001:db8::/32 fc00::/7 fe80::/10 ff00::/8
  ].map { |network| IPAddr.new(network) }.freeze

  class << self
    def canonicalize(value)
      uri = parse(value)
      validate_scheme_and_host!(uri)

      uri.scheme = uri.scheme.downcase
      uri.host = uri.host.downcase.delete_suffix(".")
      uri.fragment = nil
      uri.path = "/" if uri.path.empty?
      uri.path = uri.path.gsub(%r{/+}, "/")
      uri.port = nil if (uri.scheme == "https" && uri.port == 443) || (uri.scheme == "http" && uri.port == 80)
      uri.query = canonical_query(uri.query)
      uri.to_s
    rescue URI::Error, ArgumentError => error
      raise Invalid, error.message
    end

    def digest(value)
      Digest::SHA256.hexdigest(canonicalize(value))
    end

    def validate_public!(value, resolver: Resolv.method(:getaddresses), allow_http: false)
      canonical = canonicalize(value)
      uri = URI.parse(canonical)
      raise Invalid, "HTTP URLs are disabled" if uri.scheme == "http" && !allow_http

      addresses = resolver.call(uri.host)
      raise Invalid, "host did not resolve" if addresses.empty?

      addresses.each do |address|
        ip = IPAddr.new(address)
        raise Invalid, "host resolves to a non-public address" if BLOCKED_NETWORKS.any? { |network| network.include?(ip) }
      end
      canonical
    rescue IPAddr::InvalidAddressError => error
      raise Invalid, error.message
    end

    private

    def parse(value)
      URI.parse(value.to_s.strip)
    end

    def validate_scheme_and_host!(uri)
      raise Invalid, "URL must use HTTP or HTTPS" unless %w[http https].include?(uri.scheme&.downcase)
      raise Invalid, "URL must include a hostname" if uri.host.blank?
      raise Invalid, "URL credentials are not allowed" if uri.user || uri.password
    end

    def canonical_query(query)
      return nil if query.blank?

      pairs = URI.decode_www_form(query).reject do |key, _value|
        TRACKING_PARAMETERS.include?(key.downcase) || key.downcase.start_with?("utm_")
      end
      pairs.empty? ? nil : URI.encode_www_form(pairs.sort)
    end
  end
end
