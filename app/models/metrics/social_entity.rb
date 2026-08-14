class Metrics::SocialEntity < ApplicationRecord
  self.table_name = "metrics_social_entities"

  ENTITY_TYPES = %w[account content ad_account campaign ad].freeze

  belongs_to :parent,
    class_name: "Metrics::SocialEntity",
    optional: true
  has_many :children,
    class_name: "Metrics::SocialEntity",
    foreign_key: :parent_id,
    dependent: :destroy
  has_many :metric_observations,
    class_name: "Metrics::SocialMetricObservation",
    foreign_key: :social_entity_id,
    dependent: :destroy

  validates :id, :platform, :account_key, :source, :source_record_type,
    :source_record_id, :source_updated_at, :refreshed_at, presence: true
  validates :entity_type, inclusion: { in: ENTITY_TYPES }
end
