class Warehouse::Source::ScrapeStatus
  JOB_CLASS_NAME = Warehouse::Source::Fetcher::FetchJob.name
  FETCHER_MODEL_NAME = Warehouse::Source::Fetcher.name

  class << self
    def active(jobs: active_jobs)
      jobs.each_with_object({}) do |job, states|
        next if job.failed_execution

        source_id = source_id_for(job)
        next unless source_id

        state = job.claimed_execution ? "running" : "queued"
        states[source_id] = state if state == "running" || !states.key?(source_id)
      end
    end

    private

    def active_jobs
      SolidQueue::Job
        .where(class_name: JOB_CLASS_NAME, finished_at: nil)
        .includes(:claimed_execution, :failed_execution)
    end

    def source_id_for(job)
      global_id = GlobalID.parse(job.arguments.dig("arguments", 0, "_aj_globalid"))
      return unless global_id&.model_name == FETCHER_MODEL_NAME

      global_id.model_id.to_i
    end
  end
end
