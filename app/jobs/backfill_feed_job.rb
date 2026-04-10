class BackfillFeedJob < ApplicationJob
  queue_as :default

  BACKFILLERS = [
    SocialPost::X::Backfiller,
    SubstackPost::Backfiller
  ].freeze

  def perform
    BACKFILLERS.each do |backfiller|
      backfiller.call
    rescue => e
      Rails.logger.error "[BackfillFeedJob] #{backfiller.name} failed: #{e.message}"
    end
  end
end
