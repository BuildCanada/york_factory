module Search
  class SavedSearchFanoutJob < ApplicationJob
    queue_as :search_match

    BATCH_SIZE = 200

    def perform(at: Time.current)
      run_ids = pending_run_ids
      checkpoint = Searchable.checkpoint

      if checkpoint
        SavedSearch.transaction do
          SavedSearch.due(at).order(:next_run_at, :id).limit(BATCH_SIZE)
            .lock("FOR UPDATE SKIP LOCKED").each do |saved_search|
              scheduled_for = saved_search.next_run_at || at
              run = saved_search.runs.find_or_create_by!(scheduled_for:) do |record|
                overlap = Searchable.overlap_from_sequence(at:)
                record.from_sequence = [ saved_search.cursor_sequence, overlap ].compact.min
                record.to_sequence = checkpoint
              end
              saved_search.update_columns(
                next_run_at: next_occurrence(scheduled_for, saved_search.poll_interval_seconds, at:)
              )
              run_ids << run.id if run.status == "pending"
            end
        end
      end

      run_ids.uniq.each { |run_id| Search::RunSavedSearchJob.perform_later(run_id) }
    end

    private

    def pending_run_ids
      SavedSearchRun.joins(:saved_search)
        .merge(SavedSearch.enabled)
        .where(status: "pending")
        .order(:scheduled_for, :id)
        .limit(BATCH_SIZE)
        .pluck(:id)
    end

    def next_occurrence(scheduled_for, interval_seconds, at:)
      next_at = scheduled_for + interval_seconds.seconds
      next_at += interval_seconds.seconds while next_at <= at
      next_at
    end
  end
end
