class Warehouse::AgentRun < Warehouse::Record
  STATUSES = %w[running completed failed cancelled].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled].freeze

  has_many :kpi_documents,         dependent: :nullify
  has_many :measures,              dependent: :nullify
  has_many :extracted_observations, dependent: :nullify

  validates :agent_name, :status, :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(started_at: :desc) }
  scope :for_agent, ->(name) { where(agent_name: name) }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }

  before_validation :stamp_finished_at_on_terminal_status

  def running?
    status == "running"
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  private

  def stamp_finished_at_on_terminal_status
    self.finished_at ||= Time.current if terminal?
  end
end
