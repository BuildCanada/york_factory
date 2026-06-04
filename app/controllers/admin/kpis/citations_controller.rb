module Admin
  module Kpis
    class CitationsController < ::Admin::BaseController
      def index
        scope = Warehouse::ExtractedObservation.includes(:measure, :document, :agent_run)

        if params[:measure_id].present?
          scope = scope.where(measure_id: params[:measure_id])
        end
        if params[:agent_run_id].present?
          scope = scope.where(agent_run_id: params[:agent_run_id])
        end
        if params[:document_id].present?
          scope = scope.where(document_id: params[:document_id])
        end

        @pagy, @citations = pagy(scope.order(id: :desc), limit: 100)
      end

      def show
        @citation = Warehouse::ExtractedObservation.includes(:measure, :document, :agent_run).find(params[:id])
        @sibling_citations = Warehouse::ExtractedObservation.where(
          measure_id: @citation.measure_id,
          measurement_year: @citation.measurement_year,
          value_type: @citation.value_type,
          period_basis: @citation.period_basis
        ).where.not(id: @citation.id).includes(:document)
      end
    end
  end
end
