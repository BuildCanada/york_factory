require "test_helper"

class SubstackSubscriberImporterTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :multipart_request, :json_request

    def post_multipart(path, form:)
      @multipart_request = { path: path, form: form }
      { "csvImport" => { "id" => 13_007_494 } }
    end

    def post_json(path, payload)
      @json_request = { path: path, payload: payload }
      { "upload_date" => "2026-08-12T21:49:25.430Z" }
    end
  end

  test "uploads subscriber emails and finishes without sending welcome emails" do
    client = FakeClient.new
    subscribers = [
      Subscriber.new(email: "one@buildcanada.com"),
      Subscriber.new(email: "two@buildcanada.com")
    ]

    importer = SubstackSubscriberImporter.new(
      client: client,
      now: -> { Time.utc(2026, 8, 12, 21, 57, 1) }
    )
    import_id = importer.import!(subscribers)

    assert_equal 13_007_494, import_id
    assert_equal "/api/v1/import/prepare", client.multipart_request[:path]
    upload = client.multipart_request.dig(:form, :csv)
    assert_equal "build-canada-website-subscribers-20260812T215701Z-2.csv", upload[:filename]
    assert_equal "text/csv", upload[:content_type]
    assert_equal "email\none@buildcanada.com\ntwo@buildcanada.com\n", upload[:body].read

    assert_equal "/api/v1/import/finish", client.json_request[:path]
    assert_equal false, client.json_request.dig(:payload, :sendEmails)
    assert_equal false, client.json_request.dig(:payload, :isComp)
  end

  test "rejects a prepare response without an import ID" do
    client = FakeClient.new
    client.define_singleton_method(:post_multipart) { |*, **| { "csvImport" => {} } }

    assert_raises(SubstackSubscriberImporter::InvalidResponseError) do
      SubstackSubscriberImporter.new(client: client).import!([ Subscriber.new(email: "one@example.com") ])
    end
  end
end
