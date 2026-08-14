class Metrics::MetaAccount < ApplicationRecord
  self.table_name = "metrics_meta_accounts"

  PLATFORMS = %w[facebook instagram].freeze
  ACCOUNT_KEYS = {
    "facebook" => %w[build_canada build_toronto],
    "instagram" => %w[build_canada build_toronto]
  }.freeze

  has_many :insights,
    class_name: "Metrics::MetaAccountInsight",
    foreign_key: :meta_account_id,
    inverse_of: :account,
    dependent: :destroy
  has_many :media,
    class_name: "Metrics::MetaMedium",
    foreign_key: :meta_account_id,
    inverse_of: :account,
    dependent: :destroy

  validates :platform, inclusion: { in: PLATFORMS }
  validates :account_key, inclusion: {
    in: ACCOUNT_KEYS.values.flatten.uniq
  }
  validates :platform_account_id, presence: true
  validates :account_key, uniqueness: { scope: :platform }
  validates :platform_account_id, uniqueness: { scope: :platform }
end
