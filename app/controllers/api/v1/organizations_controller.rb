module Api
  module V1
    class OrganizationsController < ApplicationController
      def index
        orgs = Warehouse::Organization.order(:canonical_name)
        render json: orgs.select(:id, :canonical_name, :org_id_infobase)
      end

      def show
        org = Warehouse::Organization.find(params[:id])

        render json: {
          organization: org.as_json(only: [ :id, :canonical_name, :org_id_infobase ]),
          aliases: org.organization_aliases.as_json(only: [ :alias_name, :valid_from, :valid_to ]),
          fiscal_authorities: org.fiscal_authorities.order(:fiscal_year, :document_type).as_json(
            only: [ :fiscal_year, :document_type, :vote_number, :vote_type, :description, :amount ]
          ),
          fiscal_expenditures: org.fiscal_expenditures.order(:fiscal_year).as_json(
            only: [ :fiscal_year, :vote_number, :vote_type, :description, :pa_voted_ceiling, :actual_expenditure ]
          )
        }
      end
    end
  end
end
