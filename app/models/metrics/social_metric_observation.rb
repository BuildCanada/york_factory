class Metrics::SocialMetricObservation < ApplicationRecord
  self.table_name = "metrics_social_metric_observations"

  GRAINS = %w[account_day account_week account_snapshot content_snapshot entity_day].freeze
  UNITS = %w[count ratio currency seconds milliseconds].freeze

  belongs_to :social_entity,
    class_name: "Metrics::SocialEntity"

  validates :id, :entity_type, :platform, :account_key, :source,
    :source_record_type, :source_record_id, :metric_name, :source_metric_name,
    :value, :period_start, :period_end, :observed_at, :source_updated_at,
    :refreshed_at, presence: true
  validates :grain, inclusion: { in: GRAINS }
  validates :unit, inclusion: { in: UNITS }

  scope :reportable, -> { where(active: true, current_value: true, reporting_source: true) }
end
