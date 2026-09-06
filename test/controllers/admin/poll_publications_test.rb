require "test_helper"

class Admin::PollPublicationsTest < ActionDispatch::IntegrationTest
  include AdminTestHelper

  test "poll editor renders report uploads and launch copy" do
    sign_in_admin
    get new_admin_poll_path
    assert_response :success
    assert_select "select[name='poll[content_kind]']", count: 0
    assert_select "input[name='poll[analysis_pdf_en]']", count: 0
    assert_select "input[name='poll[crosstabs_json]']"
    assert_select "textarea[name='poll[subscriber_email_en]']"
    assert_select "textarea[name='poll[tweet_en]']"
    get admin_polls_path
    assert_response :success
    assert_select "form[action='#{import_publication_admin_polls_path}']"
  end

  test "only an authenticated admin can import and malformed JSON is rejected" do
    post import_publication_admin_polls_path
    assert_redirected_to new_user_session_path
    sign_in_admin
    Tempfile.create([ "publication", ".json" ]) do |file|
      file.write("not JSON")
      file.flush
      assert_no_difference "Poll.count" do
        post import_publication_admin_polls_path, params: { publication_export: Rack::Test::UploadedFile.new(file.path, "application/json") }
      end
      assert_redirected_to admin_polls_path
      assert_match "Import failed", flash[:alert]
    end
  end
  test "rejected edits retain report and image attachments and public downloads" do
    sign_in_admin
    poll = Poll.create!(slug: "asset-edit-test", title_en: "Poll", survey_slug: "survey", published_at: 1.day.ago)
    poll.crosstabs_pdf_en.attach(io: StringIO.new("%PDF-1.4 original"), filename: "analysis.pdf", content_type: "application/pdf", identify: false)
    poll.seo_image.attach(io: StringIO.new("image"), filename: "image.jpg", content_type: "image/jpeg", identify: false)
    blobs = [ poll.crosstabs_pdf_en.blob, poll.seo_image.blob ]

    patch admin_poll_path(poll), params: { poll: { sample_size: -1, purge_crosstabs_pdf_en: "1", purge_seo_image: "1" } }
    assert_response :unprocessable_entity
    poll.reload
    assert_equal blobs.map(&:id), [ poll.crosstabs_pdf_en.blob.id, poll.seo_image.blob.id ]
    assert blobs.all? { |blob| blob.service.exist?(blob.key) }
    get download_api_v1_poll_url(poll.slug, asset: "crosstabs_pdf_en")
    assert_response :success
    assert_equal "%PDF-1.4 original", response.body
  end

  test "valid edits remove attachments and replacement uploads take precedence" do
    sign_in_admin
    poll = Poll.create!(slug: "asset-remove-test", title_en: "Poll", survey_slug: "survey")
    poll.crosstabs_pdf_en.attach(io: StringIO.new("%PDF-1.4 original"), filename: "analysis.pdf", content_type: "application/pdf", identify: false)
    replacement = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 replacement"), filename: "replacement.pdf", content_type: "application/pdf", identify: false)

    patch admin_poll_path(poll), params: { poll: { purge_crosstabs_pdf_en: "1", crosstabs_pdf_en: replacement.signed_id } }
    assert_redirected_to admin_poll_path(poll)
    assert_equal replacement.id, poll.reload.crosstabs_pdf_en.blob.id
    assert_equal "%PDF-1.4 replacement", poll.crosstabs_pdf_en.download

    patch admin_poll_path(poll), params: { poll: { purge_crosstabs_pdf_en: "1" } }
    assert_redirected_to admin_poll_path(poll)
    assert_not poll.reload.crosstabs_pdf_en.attached?
  end
  test "admin creates and previews a separate poll without creating a memo" do
    sign_in_admin
    assert_no_difference "Memo.count" do
      assert_difference "Poll.count" do
        post admin_polls_path, params: { poll: { slug: "admin-poll", title_en: "Admin poll", survey_slug: "survey", body_en: "## Findings", key_messages_en: [ "Finding" ] } }
      end
    end
    poll = Poll.find_by!(slug: "admin-poll")
    assert_redirected_to admin_poll_path(poll)
    follow_redirect!
    assert_response :success
    assert_select "a[href*='/polls/admin-poll']", text: "Preview"
    assert_select "h1", text: "Admin poll"
    assert_equal [ { "message" => "Finding" } ], poll.key_messages_en
    get edit_admin_poll_path(poll)
    assert_response :success
    delete admin_poll_path(poll)
    assert_redirected_to admin_polls_path
    assert_not Poll.exists?(poll.id)
  end
end
