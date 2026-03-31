require "test_helper"

class Api::V1::FaqsControllerTest < ActionDispatch::IntegrationTest
  test "index returns published faqs ordered by position" do
    get api_v1_faqs_url
    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert data.is_a?(Array)
    positions = data.map { |f| f["position"] }
    assert_equal positions, positions.sort
  end

  test "index excludes draft faqs" do
    get api_v1_faqs_url
    data = JSON.parse(response.body)["data"]
    ids = data.map { |f| f["id"] }
    assert_not_includes ids, faqs(:draft_faq).id
  end

  test "faq serialization includes expected fields" do
    get api_v1_faqs_url
    faq_data = JSON.parse(response.body)["data"].first
    assert faq_data.key?("question")
    assert faq_data.key?("answer")
    assert faq_data.key?("position")
  end

  test "index respects french locale" do
    get api_v1_faqs_url, params: { locale: "fr" }
    assert_response :success
    data = JSON.parse(response.body)["data"]
    faq = data.find { |f| f["id"] == faqs(:published_faq).id }
    assert_equal faqs(:published_faq).question_fr, faq["question"]
  end
end
