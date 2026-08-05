require "test_helper"

class SafeUrlTest < ActiveSupport::TestCase
  test "canonicalizes a URL and removes tracking parameters" do
    url = SafeUrl.canonicalize(
      "HTTPS://WWW.NationalPost.com:443//news/story?utm_source=newsletter&b=2&a=1#comments"
    )

    assert_equal "https://www.nationalpost.com/news/story?a=1&b=2", url
    assert_equal Digest::SHA256.hexdigest(url), SafeUrl.digest(url)
  end

  test "rejects credentials and unsupported schemes" do
    assert_raises(SafeUrl::Invalid) do
      SafeUrl.canonicalize("https://user:secret@example.com/story")
    end
    assert_raises(SafeUrl::Invalid) do
      SafeUrl.canonicalize("file:///etc/passwd")
    end
  end

  test "rejects hosts resolving to private addresses" do
    error = assert_raises(SafeUrl::Invalid) do
      SafeUrl.validate_public!("https://example.com/story", resolver: ->(_host) { [ "127.0.0.1" ] })
    end

    assert_match "non-public", error.message
  end

  test "accepts a publicly resolved HTTPS URL" do
    url = SafeUrl.validate_public!(
      "https://nationalpost.com/story",
      resolver: ->(_host) { [ "8.8.8.8" ] }
    )

    assert_equal "https://nationalpost.com/story", url
  end
end
