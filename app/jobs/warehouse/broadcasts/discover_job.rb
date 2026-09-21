module Warehouse
  module Broadcasts
    class DiscoverJob < ApplicationJob
      include ActiveJob::Continuable

      MAX_ENTRIES = 100

      def perform
        now = Time.current
        entries = adapter.discover
        raise HttpClient::PermanentError, "CPAC listing exceeded #{MAX_ENTRIES} entries" if entries.size > MAX_ENTRIES
        step :upsert_streams do |step|
          start_index = entries.index { |entry| entry.external_id == step.cursor }
          entries.drop(start_index ? start_index + 1 : 0).each do |entry|
            upsert(entry, now:)
            step.set!(entry.external_id)
          end
        end
        step :dispatch do
          DispatchCapturesJob.perform_later
        end
      end

      private

      def adapter
        @adapter ||= CpacAdapter.new
      end

      def capture_enabled_by_default?
        ActiveModel::Type::Boolean.new.cast(ENV["CPAC_CAPTURE_ENABLED"]) == true
      end

      def upsert(entry, now:)
        stream = MediaStream.find_or_initialize_by(provider: "cpac", external_id: entry.external_id)
        stream.assign_attributes(
          kind: entry.kind, title_en: entry.title_en, title_fr: entry.title_fr,
          description_en: entry.description_en, description_fr: entry.description_fr,
          page_url_en: entry.page_url_en, page_url_fr: entry.page_url_fr,
          manifest_url: entry.manifest_url, provider_state: entry.provider_state,
          scheduled_start_at: entry.scheduled_start_at,
          metadata: stream.metadata.merge(entry.metadata),
          first_seen_at: stream.first_seen_at || now, last_seen_at: now
        )
        stream.save!
        state = MediaCaptureState.find_or_create_by!(media_stream_id: stream.id) do |new_state|
          new_state.enabled = capture_enabled_by_default?
          new_state.next_poll_at = initial_poll_at(entry, now:)
        end
        if state.enabled? && entry.provider_state == "live" && state.last_captured_at.nil? &&
            (state.lease_expires_at.nil? || state.lease_expires_at <= now) && state.next_poll_at.to_i > now.to_i
          state.update!(next_poll_at: now)
        end
      end

      def initial_poll_at(entry, now:)
        return now unless entry.provider_state == "prelive" && entry.scheduled_start_at&.future?

        [ entry.scheduled_start_at - 30.seconds, now ].max
      end
    end
  end
end
