require "test_helper"

class Api::V1::SubscribersControllerTest < ActionDispatch::IntegrationTest
  test "create with valid email creates subscriber" do
    assert_difference "Subscriber.count", 1 do
      post api_v1_subscribers_url, params: {
        subscriber: {
          first_name: "Jane",
          last_name: "Doe",
          email: "janedoe@example.com",
          postal_code: "T2P 1J9"
        }
      }, as: :json
    end

    assert_response :created
    data = JSON.parse(response.body)
    assert_equal "Subscribed", data["message"]
  end

  test "create enqueues a HubSpot form submission for the new subscriber" do
    assert_enqueued_with(job: Subscriber::SubmitToHubspotFormJob) do
      post api_v1_subscribers_url, params: {
        subscriber: { email: "syncme@example.com" }
      }, as: :json
    end
  end

  test "create stores the hubspot_form source and tracking context" do
    post api_v1_subscribers_url, params: {
      subscriber: {
        email: "tracked@example.com",
        first_name: "Jane",
        last_name: "Doe",
        postal_code: "T2P 1J9",
        placement: "navbar",
        page_uri: "https://buildcanada.com/memos/some-memo",
        page_name: "Some Memo | Build Canada",
        hubspot_utk: "utk-cookie",
        ip_address: "203.0.113.7"
      }
    }, as: :json

    assert_response :created
    subscriber = Subscriber.find_by!(email: "tracked@example.com")
    assert_equal "hubspot_form", subscriber.source
    assert_equal "navbar", subscriber.placement
    assert_equal "https://buildcanada.com/memos/some-memo", subscriber.page_uri
    assert_equal "Some Memo | Build Canada", subscriber.page_name
    assert_equal "utk-cookie", subscriber.hubspot_utk
    assert_equal "203.0.113.7", subscriber.ip_address
  end

  test "create with duplicate email returns 422" do
    assert_no_difference "Subscriber.count" do
      post api_v1_subscribers_url, params: {
        subscriber: { email: "test@example.com" }
      }, as: :json
    end

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert data.key?("errors")
    assert data["errors"].any? { |e| e.include?("Email") }
  end

  test "create without email returns 422" do
    assert_no_difference "Subscriber.count" do
      post api_v1_subscribers_url, params: {
        subscriber: { first_name: "Nobody" }
      }, as: :json
    end

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert data.key?("errors")
    assert data["errors"].any? { |e| e.include?("Email") }
  end

  test "create with malformed email returns 422" do
    assert_no_difference "Subscriber.count" do
      post api_v1_subscribers_url, params: {
        subscriber: { email: "not-an-email" }
      }, as: :json
    end

    assert_response :unprocessable_entity
  end
end
