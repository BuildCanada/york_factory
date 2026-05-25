module Admin
  module Kpis
    class AgentRunsController < ::Admin::BaseController
      def index
        scope = Warehouse::AgentRun.recent
        scope = scope.for_agent(params[:agent]) if params[:agent].present?
        scope = scope.where(status: params[:status]) if params[:status].present?

        @pagy, @runs = pagy(scope, limit: 50)
        @counts_by_agent = Warehouse::AgentRun.group(:agent_name).count.sort_by { |_, c| -c }
        @counts_by_status = Warehouse::AgentRun.group(:status).count
      end

      def show
        @run = Warehouse::AgentRun.find(params[:id])
        @citation_count = Warehouse::MeasureCitation.where(agent_run_id: @run.id).count
        @measure_count  = Warehouse::Measure.where(agent_run_id: @run.id).count
        @document_count = Warehouse::KpiDocument.where(agent_run_id: @run.id).count
      end
    end
  end
end
