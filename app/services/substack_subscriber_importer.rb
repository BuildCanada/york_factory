require "csv"
require "stringio"

class SubstackSubscriberImporter
  class InvalidResponseError < Metrics::SubstackClient::Error; end

  def initialize(client:, now: -> { Time.current })
    @client = client
    @now = now
  end

  def import!(subscribers)
    subscribers = subscribers.to_a
    raise ArgumentError, "at least one subscriber is required" if subscribers.empty?

    prepared = @client.post_multipart(
      "/api/v1/import/prepare",
      form: { csv: csv_upload(subscribers) }
    )
    import_id = prepared.dig("csvImport", "id")
    raise InvalidResponseError, "Substack import prepare response omitted the import ID" if import_id.blank?

    @client.post_json(
      "/api/v1/import/finish",
      {
        csvImportId: import_id,
        isComp: false,
        extendComp: true,
        sendEmails: false,
        emailListOrigin: "Our website",
        sectionImportContext: false
      }
    )

    import_id
  end

  private

  def csv_upload(subscribers)
    body = CSV.generate do |csv|
      csv << [ "email" ]
      subscribers.each { |subscriber| csv << [ subscriber.email ] }
    end

    {
      body: StringIO.new(body),
      filename: import_filename(subscribers.size),
      content_type: "text/csv"
    }
  end

  def import_filename(subscriber_count)
    timestamp = @now.call.utc.strftime("%Y%m%dT%H%M%SZ")
    "build-canada-website-subscribers-#{timestamp}-#{subscriber_count}.csv"
  end
end
