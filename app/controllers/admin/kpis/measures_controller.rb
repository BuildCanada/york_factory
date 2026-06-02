module Admin
  module Kpis
    class MeasuresController < ::Admin::BaseController
      def index
        scope = Warehouse::Measure.includes(:unit, organization: :jurisdiction)

        if params[:jurisdiction].present?
          jur = Warehouse::Jurisdiction.find_by(slug: params[:jurisdiction])
          scope = scope.joins(:organization).where("warehouse.organizations.jurisdiction_id" => jur&.id)
        end
        if params[:organization].present?
          scope = scope.joins(:organization).where("warehouse.organizations.slug" => params[:organization])
        end
        if params[:q].present?
          scope = scope.where("warehouse.measures.canonical_name ILIKE ?", "%#{params[:q]}%")
        end

        @jurisdictions = Warehouse::Jurisdiction.order(:name)
        @pagy, @measures = pagy(scope.order(:canonical_name), limit: 50)
      end

      def show
        @measure = Warehouse::Measure.includes(:unit, organization: :jurisdiction).find(params[:id])
        @facts = Warehouse::MeasureFact.where(measure_id: @measure.id)
          .order(measurement_year: :desc, value_type: :asc)
          .limit(50)
        @citation_count = @measure.extracted_observations.count
        @run_count = Warehouse::ExtractedObservation.where(measure_id: @measure.id).distinct.count(:agent_run_id)
      end
    end
  end
end
