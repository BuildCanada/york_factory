class Metrics::RefreshSocialAnalyticsJob < ApplicationJob
  queue_as :default

  def perform
    Metrics::SocialAnalyticsRefresh.new.call
  end
end
