module Metrics
  class InstagramStat < ApplicationRecord
    belongs_to :social_media_account,
      class_name: "Metrics::SocialMediaAccount",
      optional: true

    ACCOUNTS = %w[build_canada build_toronto].freeze

    METRIC_COLUMNS = %w[views interactions new_followers].freeze

    validates :account, presence: true, inclusion: { in: ACCOUNTS }
    validates :date, presence: true
    validates :date, uniqueness: { scope: :account }
    validate :date_must_be_monday

    scope :for_account, ->(account) { where(account: account) }
    scope :recent_first, -> { order(date: :desc) }
    scope :filled, -> { where.not(views: nil).where.not(interactions: nil).where.not(new_followers: nil) }

    def filled?
      views.present? && interactions.present? && new_followers.present?
    end

    def week_end
      date && date + 6
    end

    private

    def date_must_be_monday
      return if date.blank?

      errors.add(:date, "must be a Monday (week start)") unless date.monday?
    end
  end
end
