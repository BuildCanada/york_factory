module Warehouse
  module Broadcasts
    class BackfillJob < ApplicationJob
      include ActiveJob::Continuable
      self.enqueue_after_transaction_commit = true

      MAX_PAGE_ENTRIES = 100
      MAX_PAGES_PER_EXECUTION = 5
      MAX_DISPATCHES_PER_EXECUTION = 100

      def perform(request_id, lease_token)
        @request = BroadcastBackfillRequest.find(request_id)
        return if @request.state == "completed"
        return unless @request.renew_lease!(lease_token)
        if @request.orchestration_complete?
          @request.refresh_progress!
          @request.release_lease!(lease_token)
          return
        end

        @request.update!(state: "running", started_at: @request.started_at || Time.current, error: nil)
        if @request.scope == "date_range"
          resume_date = [ @request.starts_on + @request.processed_dates, @request.ends_on + 1 ].min
          step :discover, start: [ resume_date.iso8601, 1 ] do |continuation|
            discover(continuation, lease_token:)
          end
        end
        step :dispatch do |continuation|
          dispatch(continuation, lease_token:)
        end
        step :finish do
          @request.update!(orchestration_complete: true)
          @request.refresh_progress!
          @request.release_lease!(lease_token)
        end
      rescue StandardError => error
        @request&.record_lease_error!(lease_token, error)
        raise
      end

      private

      def discover(continuation, lease_token:)
        date = Date.iso8601(continuation.cursor.fetch(0))
        page_number = Integer(continuation.cursor.fetch(1))
        pages_processed = 0
        while date <= @request.ends_on
          raise Capturer::LeaseLost, "backfill request lease expired" unless @request.renew_lease!(lease_token)

          page = adapter.list(start_date: date, end_date: date, page: page_number)
          if page.entries.size > MAX_PAGE_ENTRIES
            raise HttpClient::PermanentError, "CPAC history page exceeded #{MAX_PAGE_ENTRIES} entries"
          end
          page.entries.each { |entry| remember(entry) }
          remember_errors(page.errors) if page.errors.present?

          if page.next_page.present?
            page_number = Integer(page.next_page)
          else
            @request.update!(processed_dates: (date - @request.starts_on).to_i + 1)
            date += 1
            page_number = 1
          end
          continuation.set!([ date.iso8601, page_number ])
          @request.refresh_progress!
          pages_processed += 1
          interrupt!(reason: :batch_limit) if pages_processed >= MAX_PAGES_PER_EXECUTION && date <= @request.ends_on
        end
      end

      def dispatch(continuation, lease_token:)
        dispatched = 0
        @request.items.where("id > ?", continuation.cursor.to_i).order(:id).find_each do |item|
          raise Capturer::LeaseLost, "backfill request lease expired" unless @request.renew_lease!(lease_token)

          if @request.mode == "discover_and_queue"
            item.enqueue!
          else
            item.update!(state: "skipped", error: nil, finished_at: Time.current)
            @request.refresh_progress!
          end
          continuation.set!(item.id)
          dispatched += 1
          interrupt!(reason: :batch_limit) if dispatched >= MAX_DISPATCHES_PER_EXECUTION
        end
      end

      def remember(entry)
        now = Time.current
        stream = MediaStream.find_or_initialize_by(provider: "cpac", external_id: entry.external_id)
        stream.assign_attributes(
          kind: "on_demand", title_en: entry.title_en, title_fr: entry.title_fr,
          description_en: entry.description_en, description_fr: entry.description_fr,
          page_url_en: entry.page_url_en, page_url_fr: entry.page_url_fr,
          manifest_url: entry.manifest_url, provider_state: entry.provider_state,
          scheduled_start_at: entry.scheduled_start_at,
          metadata: stream.metadata.merge(entry.metadata),
          first_seen_at: stream.first_seen_at || now, last_seen_at: now
        )
        stream.save!
        @request.items.find_or_create_by!(media_stream: stream)
      end

      def remember_errors(errors)
        existing = Array(@request.metadata["listing_errors"])
        new_errors = errors.is_a?(Array) ? errors : [ errors ]
        combined = (existing + new_errors).uniq { |item| item.slice("url", "external_id", "error") }.last(500)
        @request.update!(
          metadata: @request.metadata.merge("listing_errors" => combined),
          error: "#{combined.size} historical listing #{'entry'.pluralize(combined.size)} could not be read"
        )
      end

      def adapter
        @adapter ||= CpacHistoryAdapter.new
      end
    end
  end
end
