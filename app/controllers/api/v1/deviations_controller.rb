module Api
  module V1
    class DeviationsController < ApplicationController
      def index
        deviations = Warehouse::SpendingDeviation.includes(:organization)

        deviations = deviations.for_year(params[:fiscal_year]) if params[:fiscal_year].present?
        deviations = deviations.anomalous if params[:anomalous] == "true"

        render json: deviations.map { |d|
          {
            organization: d.organization.canonical_name,
            fiscal_year: d.fiscal_year,
            vote_number: d.vote_number,
            vote_type: d.vote_type,
            consolidated_estimate: d.consolidated_estimate,
            actual_expenditure: d.actual_expenditure,
            variance_amount: d.variance_amount,
            variance_pct: d.variance_pct
          }
        }
      end
    end
  end
end
