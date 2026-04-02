require "test_helper"

# Test Localizable concern via the memos endpoint, which uses CmsBaseController
# (which includes Localizable).
class LocalizableTest < ActionDispatch::IntegrationTest
  test "defaults to English locale" do
    get api_v1_memo_url("housing-crisis-memo")
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Housing Crisis Analysis", data["title"]
  end

  test "locale=fr sets French locale" do
    get api_v1_memo_url("housing-crisis-memo"), params: { locale: "fr" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Analyse de la crise du logement", data["title"]
  end

  test "Accept-Language: fr sets French locale" do
    get api_v1_memo_url("housing-crisis-memo"),
        headers: { "Accept-Language" => "fr" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Analyse de la crise du logement", data["title"]
  end

  test "unsupported locale falls back to English" do
    get api_v1_memo_url("housing-crisis-memo"), params: { locale: "es" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Housing Crisis Analysis", data["title"]
  end

  test "locale param takes precedence over Accept-Language header" do
    get api_v1_memo_url("housing-crisis-memo"),
        params: { locale: "en" },
        headers: { "Accept-Language" => "fr" }
    assert_response :success

    data = JSON.parse(response.body)
    assert_equal "Housing Crisis Analysis", data["title"]
  end
end
