module Admin
  module Metrics
    class LinkedinStatsController < Admin::BaseController
      def index
        @account = params[:account].presence
        scope = ::Metrics::LinkedinStat.recent_first
        scope = scope.for_account(@account) if @account.present?
        @stats = scope.limit(100)
      end

      def import
        account = params[:account]
        file = params[:file]

        fallback = admin_metrics_linkedin_stats_path

        if account.blank? || !::Metrics::LinkedinStat::ACCOUNTS.include?(account)
          redirect_back fallback_location: fallback, alert: "Please select a valid account."
          return
        end

        if file.blank?
          redirect_back fallback_location: fallback, alert: "Please select an XLS file."
          return
        end

        result = ::Metrics::LinkedinStat.upsert_from_xls(account, file.path)

        summary = "#{result[:inserted]} new, #{result[:updated]} updated"

        if result[:errors].any?
          redirect_back fallback_location: fallback,
            alert: "Import completed: #{summary}, #{result[:errors].size} errors. #{result[:errors].first(3).join('; ')}"
        else
          redirect_back fallback_location: fallback,
            notice: "Import complete: #{summary}."
        end
      end
    end
  end
end
