require "ipaddr"
require "resolv"
require "net/http"

module Oauth
  # Fetches a URL named by an untrusted party (a Client ID Metadata Document),
  # guarding against server-side request forgery (CIMD draft §6, MCP
  # "Authorization Server Abuse Protection"):
  #
  # - HTTPS only, on port 443.
  # - The host is resolved once, every address must be public, and the
  #   connection goes to the checked address (so DNS rebinding can't swap it).
  # - No redirects, a 5-second deadline and a 64 KB body cap.
  #
  #   response = Oauth::SafeFetch.get("https://app.example.com/client.json")
  #   response.status   # => 200
  #   response.headers  # => { "cache-control" => "max-age=3600", ... }
  #   response.body     # => "{...}"
  module SafeFetch
    Response = Data.define(:status, :headers, :body)

    class Error < StandardError; end

    TIMEOUT = 5
    MAX_BYTES = 64 * 1024
    USER_AGENT = "BuildCanada-OAuth/1.0 (+https://data.buildcanada.com/api/mcp)".freeze

    # Addresses no fetch may reach, beyond IPAddr's private/loopback/link-local.
    BLOCKED_RANGES = %w[
      0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 192.0.2.0/24 198.18.0.0/15 198.51.100.0/24
      203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 255.255.255.255/32
      ::/128 64:ff9b::/96 100::/64 2001:db8::/32 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    module_function

    def get(url, timeout: TIMEOUT, max_bytes: MAX_BYTES)
      uri = URI.parse(url)
      raise Error, "must be an https URL" unless uri.is_a?(URI::HTTPS) && uri.host.present?
      raise Error, "must use the default https port" unless uri.port == 443
      raise Error, "must not contain user info" if uri.userinfo

      address = public_address!(uri.host)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = address
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout
      http.ssl_timeout = timeout

      request = Net::HTTP::Get.new(uri.request_uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = USER_AGENT

      http.start do
        http.request(request) do |response|
          body = +""
          response.read_body do |chunk|
            body << chunk
            raise Error, "response is larger than #{max_bytes / 1024} KB" if body.bytesize > max_bytes
            raise Error, "took longer than #{timeout} seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          end
          return Response.new(status: response.code.to_i, headers: response.each_header.to_h, body:)
        end
      end
    rescue URI::InvalidURIError
      raise Error, "isn't a valid URL"
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, SocketError, OpenSSL::SSL::SSLError, IOError => error
      raise Error, "couldn't be fetched (#{error.class.name.demodulize})"
    end

    def public_address!(host)
      addresses = Resolv.getaddresses(host)
      raise Error, "host doesn't resolve" if addresses.empty?

      addresses.each do |address|
        raise Error, "host resolves to a non-public address" unless public_ip?(address)
      end
      addresses.first
    end

    def public_ip?(address)
      ip = IPAddr.new(address)
      ip = ip.native if ip.ipv4_mapped?
      return false if ip.private? || ip.loopback? || ip.link_local?
      return false if ip.ipv6? && IPAddr.new("fc00::/7").include?(ip)

      BLOCKED_RANGES.none? { |range| range.family == ip.family && range.include?(ip) }
    rescue IPAddr::Error
      false
    end
  end
end
