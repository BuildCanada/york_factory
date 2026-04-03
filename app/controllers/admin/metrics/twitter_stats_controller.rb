module Admin
  module Metrics
    class TwitterStatsController < Admin::BaseController
      def index
        @account = params[:account].presence
        scope = ::Metrics::TwitterStat.recent_first
        scope = scope.for_account(@account) if @account.present?
        @stats = scope.limit(100)
      end

      def import
        account = params[:account]
        file = params[:file]

        if account.blank? || !::Metrics::TwitterStat::ACCOUNTS.include?(account)
          redirect_to admin_metrics_twitter_stats_path, alert: "Please select a valid account."
          return
        end

        if file.blank?
          redirect_to admin_metrics_twitter_stats_path, alert: "Please select a CSV file."
          return
        end

        result = ::Metrics::TwitterStat.upsert_from_csv(account, file.read)

        summary = "#{result[:inserted]} new, #{result[:updated]} updated"

        if result[:errors].any?
          redirect_to admin_metrics_twitter_stats_path(account: account),
            alert: "Import completed: #{summary}, #{result[:errors].size} errors. #{result[:errors].first(3).join('; ')}"
        else
          redirect_to admin_metrics_twitter_stats_path(account: account),
            notice: "Import complete: #{summary}."
        end
      end
    end
  end
end
