require "test_helper"

class TestCpacDiscoverJob < Warehouse::Broadcasts::DiscoverJob
  cattr_accessor :entries

  private

  def adapter
    Struct.new(:entries) { def discover = entries }.new(self.class.entries)
  end
end

class Warehouse::Broadcasts::DiscoverJobTest < ActiveJob::TestCase
  setup do
    @external_id = SecureRandom.uuid
    TestCpacDiscoverJob.entries = [ Warehouse::Broadcasts::CpacAdapter::Stream.new(
      external_id: @external_id, kind: "event", title_en: "Event", title_fr: "Événement",
      description_en: "Description", description_fr: "Description",
      page_url_en: "https://www.cpac.ca/event", page_url_fr: "https://www.cpac.ca/evenement",
      manifest_url: "https://cpac-ca-live.cdn.vustreams.com/event/master.m3u8",
      provider_state: "live", scheduled_start_at: Time.current,
      metadata: { "cpac_type" => "live" }
    ) ]
  end

  test "upserts discovery metadata and creates capture disabled by default" do
    previous = ENV.delete("CPAC_CAPTURE_ENABLED")
    assert_enqueued_with(job: Warehouse::Broadcasts::DispatchCapturesJob) do
      TestCpacDiscoverJob.perform_now
    end

    stream = Warehouse::MediaStream.find_by!(provider: "cpac", external_id: @external_id)
    assert_equal "Event", stream.title_en
    assert_equal "live", stream.metadata.fetch("cpac_type")
    assert_not stream.capture_state.enabled?

    stream.update!(metadata: stream.metadata.merge("operator_note" => "keep"))
    TestCpacDiscoverJob.perform_now
    assert_equal "keep", stream.reload.metadata.fetch("operator_note")
  ensure
    ENV["CPAC_CAPTURE_ENABLED"] = previous
  end
end
