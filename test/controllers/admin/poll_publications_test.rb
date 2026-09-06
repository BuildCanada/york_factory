require "test_helper"

class Admin::PollPublicationsTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  test "poll editor renders report uploads and launch copy" do
    sign_in_admin
    get new_admin_memo_path
    assert_response :success
    assert_select "select[name='memo[content_kind]']"
    assert_select "input[name='memo[analysis_pdf_en]']"
    assert_select "textarea[name='memo[subscriber_email_en]']"
    assert_select "textarea[name='memo[tweet_en]']"
    get admin_memos_path
    assert_response :success
    assert_select "form[action='#{import_poll_admin_memos_path}']"
  end

  test "only an authenticated admin can import and malformed JSON is rejected" do
    post import_poll_admin_memos_path
    assert_redirected_to new_user_session_path
    sign_in_admin
    Tempfile.create([ "publication", ".json" ]) do |file|
      file.write("not JSON")
      file.flush
      assert_no_difference "Memo.count" do
        post import_poll_admin_memos_path, params: { publication_export: Rack::Test::UploadedFile.new(file.path, "application/json") }
      end
      assert_redirected_to admin_memos_path
      assert_match "Import failed", flash[:alert]
    end
  end
  test "rejected edits retain report and image attachments and public downloads" do
    sign_in_admin
    memo = Memo.create!(slug: "asset-edit-test", title_en: "Poll", content_kind: "poll", survey_slug: "survey", published_at: 1.day.ago)
    memo.analysis_pdf_en.attach(io: StringIO.new("%PDF-1.4 original"), filename: "analysis.pdf", content_type: "application/pdf", identify: false)
    memo.seo_image.attach(io: StringIO.new("image"), filename: "image.jpg", content_type: "image/jpeg", identify: false)
    blobs = [ memo.analysis_pdf_en.blob, memo.seo_image.blob ]

    patch admin_memo_path(memo), params: { memo: { sample_size: -1, purge_analysis_pdf_en: "1", purge_seo_image: "1" } }
    assert_response :unprocessable_entity
    memo.reload
    assert_equal blobs.map(&:id), [ memo.analysis_pdf_en.blob.id, memo.seo_image.blob.id ]
    assert blobs.all? { |blob| blob.service.exist?(blob.key) }
    get download_api_v1_memo_url(memo.slug, asset: "analysis_pdf_en")
    assert_response :success
    assert_equal "%PDF-1.4 original", response.body
  end

  test "valid edits remove attachments and replacement uploads take precedence" do
    sign_in_admin
    memo = Memo.create!(slug: "asset-remove-test", title_en: "Poll", content_kind: "poll", survey_slug: "survey")
    memo.analysis_pdf_en.attach(io: StringIO.new("%PDF-1.4 original"), filename: "analysis.pdf", content_type: "application/pdf", identify: false)
    replacement = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 replacement"), filename: "replacement.pdf", content_type: "application/pdf", identify: false)

    patch admin_memo_path(memo), params: { memo: { purge_analysis_pdf_en: "1", analysis_pdf_en: replacement.signed_id } }
    assert_redirected_to admin_memo_path(memo)
    assert_equal replacement.id, memo.reload.analysis_pdf_en.blob.id
    assert_equal "%PDF-1.4 replacement", memo.analysis_pdf_en.download

    patch admin_memo_path(memo), params: { memo: { purge_analysis_pdf_en: "1" } }
    assert_redirected_to admin_memo_path(memo)
    assert_not memo.reload.analysis_pdf_en.attached?
  end
end
