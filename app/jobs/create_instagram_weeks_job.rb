class CreateInstagramWeeksJob < ApplicationJob
  queue_as :default

  START_DATE = Date.new(2026, 1, 26).freeze

  def perform
    last_completed_monday = Date.current.beginning_of_week(:monday) - 7

    Metrics::InstagramStat::ACCOUNTS.each do |account|
      create_missing_weeks(account, last_completed_monday)
    end
  end

  private

  def create_missing_weeks(account, last_monday)
    existing = Metrics::InstagramStat
      .for_account(account)
      .where(date: START_DATE..last_monday)
      .pluck(:date)
      .to_set

    monday = START_DATE
    while monday <= last_monday
      Metrics::InstagramStat.create!(account: account, date: monday) unless existing.include?(monday)
      monday += 7
    end
  end
end
