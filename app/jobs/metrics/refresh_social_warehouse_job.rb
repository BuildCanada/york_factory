class Metrics::RefreshSocialWarehouseJob < ApplicationJob
  queue_as :default

  def perform
    Metrics::SocialWarehouseRefresh.new.call
  end
end
