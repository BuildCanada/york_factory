require "csv"

module Admin
  module Developers
    class AuditEventsController < BaseController
      CSV_LIMIT = 50_000

      def index
        scope = AuditEvent.recent.includes(:actor_user)
        scope = scope.where(account_id: params[:account_id]) if params[:account_id].present?
        scope = scope.where("action LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(params[:action_prefix])}%") if params[:action_prefix].present?

        respond_to do |format|
          format.html { @pagy, @audit_events = pagy(scope) }
          format.csv do
            send_data to_csv(scope.limit(CSV_LIMIT)), filename: "audit-events-#{Date.current.iso8601}.csv", type: "text/csv"
          end
        end
      end

      private

      def to_csv(events)
        CSV.generate do |csv|
          csv << %w[created_at account_id actor_kind actor_user_id action subject_type subject_id ip user_agent metadata]
          events.each do |event|
            csv << [ event.created_at.iso8601, event.account_id, event.actor_kind, event.actor_user_id, event.action,
                     event.subject_type, event.subject_id, event.ip, event.user_agent, event.metadata.to_json ]
          end
        end
      end
    end
  end
end
