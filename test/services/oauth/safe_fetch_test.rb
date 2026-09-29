require "test_helper"

# The SSRF guard used for Client ID Metadata Documents.
class Oauth::SafeFetchTest < ActiveSupport::TestCase
  test "only public addresses are allowed" do
    %w[93.184.216.34 2606:4700::1111].each { |ip| assert Oauth::SafeFetch.public_ip?(ip), ip }
    %w[127.0.0.1 10.0.0.5 172.16.0.1 192.168.1.1 169.254.169.254 100.64.0.1 0.0.0.0 224.0.0.1 ::1 fc00::1 fe80::1
       ::ffff:127.0.0.1 ::ffff:10.0.0.1 not-an-ip].each { |ip| assert_not Oauth::SafeFetch.public_ip?(ip), ip }
  end

  test "refuses non-https URLs, other ports and user info" do
    [ "http://example.com/c.json", "https://example.com:8443/c.json", "https://u:p@example.com/c.json", "ftp://example.com/c" ].each do |url|
      assert_raises(Oauth::SafeFetch::Error, url) { Oauth::SafeFetch.get(url) }
    end
  end

  test "refuses hosts that resolve to private addresses" do
    Resolv.stub(:getaddresses, [ "93.184.216.34", "10.0.0.1" ]) do
      error = assert_raises(Oauth::SafeFetch::Error) { Oauth::SafeFetch.get("https://rebind.example/c.json") }
      assert_match "non-public", error.message
    end
    Resolv.stub(:getaddresses, []) do
      assert_raises(Oauth::SafeFetch::Error) { Oauth::SafeFetch.get("https://nowhere.example/c.json") }
    end
  end
end
