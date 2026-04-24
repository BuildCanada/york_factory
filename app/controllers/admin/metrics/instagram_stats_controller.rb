module Admin
  module Metrics
    class InstagramStatsController < Admin::BaseController
      before_action :set_stat, only: [ :edit, :update, :destroy ]

      def index
        @account = params[:account].presence
        scope = ::Metrics::InstagramStat.recent_first
        scope = scope.for_account(@account) if @account.present?
        @stats = scope.limit(100)
      end

      def new
        @stat = ::Metrics::InstagramStat.new(
          account: params[:account].presence || ::Metrics::InstagramStat::ACCOUNTS.first,
          date: default_week_start
        )
      end

      def create
        @stat = ::Metrics::InstagramStat.new(stat_params)
        if @stat.save
          redirect_to admin_metrics_instagram_stats_path(account: @stat.account),
            notice: "Instagram stats saved for week of #{@stat.date.strftime('%Y-%m-%d')}."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit; end

      def update
        if @stat.update(stat_params)
          redirect_to admin_metrics_instagram_stats_path(account: @stat.account),
            notice: "Instagram stats updated for week of #{@stat.date.strftime('%Y-%m-%d')}."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @stat.destroy!
        redirect_to admin_metrics_instagram_stats_path, notice: "Instagram stats deleted."
      end

      def generate_weeks
        before = ::Metrics::InstagramStat.count
        CreateInstagramWeeksJob.new.perform
        created = ::Metrics::InstagramStat.count - before
        redirect_to admin_metrics_instagram_stats_path(account: params[:account]),
          notice: "Generated #{created} new week#{'s' if created != 1}."
      end

      private

      def set_stat
        @stat = ::Metrics::InstagramStat.find(params[:id])
      end

      def stat_params
        params.require(:metrics_instagram_stat).permit(
          :account, :date, :views, :interactions, :new_followers
        )
      end

      def default_week_start
        Date.current.beginning_of_week(:monday)
      end
    end
  end
end
