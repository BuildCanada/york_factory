module Api
  module V1
    module Kpis
      module Admin
        class AgentRunsController < BaseController
          def create
            attrs = params.require(:agent_run).permit(
              :agent_name, :agent_version, input_params: {}
            ).to_h.symbolize_keys

            run = ::Warehouse::AgentRun.create!(
              agent_name: attrs.fetch(:agent_name),
              agent_version: attrs[:agent_version],
              input_params: attrs[:input_params] || {},
              status: "running",
              started_at: Time.current,
              triggered_by: api_token.name
            )

            render json: serialize(run, include_report: true), status: :ok
          end

          def update
            run = ::Warehouse::AgentRun.find(params[:id])
            attrs = params.require(:agent_run).permit(
              :status, :report, :error_message, summary: {}
            ).to_h.symbolize_keys

            run.assign_attributes(attrs.compact)
            run.save!

            render json: serialize(run, include_report: true), status: :ok
          end

          def show
            run = ::Warehouse::AgentRun.find(params[:id])
            render json: serialize(run, include_report: true)
          end

          private

          def serialize(run, include_report: false)
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
end
