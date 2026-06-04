module Api
  module V1
    module Kpis
      class AgentRunsController < BaseController
        def index
          scope = ::Warehouse::AgentRun.recent
          scope = scope.for_agent(params[:agent]) if params[:agent].present?
          scope = scope.where(status: params[:status]) if params[:status].present?

          pagy, runs = pagy(scope, limit: (params[:per_page] || 50).to_i)

          render json: {
            data: runs.map { |r| serialize(r, include_report: false) },
            meta: pagy_metadata(pagy)
          }
        end

        def show
          run = ::Warehouse::AgentRun.find(params[:id])
          render json: serialize(run, include_report: true)
        end

        private

        def serialize(run, include_report:)
          base = {
            id: run.id,
            agent_name: run.agent_name,
            agent_version: run.agent_version,
            status: run.status,
            input_params: run.input_params,
            summary: run.summary,
            triggered_by: run.triggered_by,
            started_at: run.started_at,
            finished_at: run.finished_at,
            error_message: run.error_message
          }
          base[:report] = run.report if include_report
          base
        end
      end
    end
  end
end
