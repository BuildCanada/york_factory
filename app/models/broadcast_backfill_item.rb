class BroadcastBackfillItem < ApplicationRecord
  STATES = %w[discovered queued running completed failed skipped].freeze

  belongs_to :request, class_name: "BroadcastBackfillRequest", inverse_of: :items
  belongs_to :media_stream, class_name: "Warehouse::MediaStream"

  validates :media_stream_id, uniqueness: { scope: :request_id }
  validates :state, inclusion: { in: STATES }

  scope :failed, -> { where(state: "failed") }

  def enqueue!
    with_lock do
      return self if state.in?(%w[queued running completed])
      raise ArgumentError, "stream has no historical media source" unless historical_source?

      Warehouse::Broadcasts::HistoricalCaptureJob.perform_later(media_stream_id, id)
      update!(state: "queued", error: nil, queued_at: Time.current, started_at: nil, finished_at: nil)
    end
    request.refresh_progress!
    self
  rescue StandardError => error
    update!(state: "failed", error: "#{error.class}: #{error.message}".truncate(2_000), finished_at: Time.current)
    request.refresh_progress!
    raise
  end

  def mark_running!
    update!(state: "running", error: nil, started_at: started_at || Time.current, finished_at: nil)
    request.refresh_progress!
  end

  def mark_completed!
    update!(state: "completed", error: nil, finished_at: Time.current)
    request.refresh_progress!
  end

  def mark_failed!(error)
    update!(state: "failed", error: "#{error.class}: #{error.message}".truncate(2_000), finished_at: Time.current)
    request.refresh_progress!
  end

  def historical_source?
    media_stream.provider == "cpac" && media_stream.kind == "on_demand"
  end
end
