class Warehouse::Source::ScrapeSchedule
  TASK_KEY_BY_PREFIX = {
    "econ_" => "fetch_economy_sources",
    "spending_" => "fetch_spending_sources",
    "election_" => "fetch_election_sources"
  }.freeze

  class << self
    def configured_tasks
      recurring_config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml"))
        .fetch("production")

      TASK_KEY_BY_PREFIX.values.filter_map do |key|
        options = recurring_config[key]
        SolidQueue::RecurringTask.from_configuration(key, **options.symbolize_keys) if options
      end
    end
  end

  def initialize(tasks: self.class.configured_tasks)
    @tasks = tasks.index_by(&:key)
  end

  def next_run_at(source, from: Time.current)
    task_for(source)&.next_time_after(from)
  end

  def schedule_for(source)
    task_for(source)&.schedule
  end

  private

  attr_reader :tasks

  def task_for(source)
    return unless source.automatically_scraped?

    prefix, task_key = TASK_KEY_BY_PREFIX.find { |candidate, _| source.name.start_with?(candidate) }
    tasks[task_key] if prefix
  end
end
