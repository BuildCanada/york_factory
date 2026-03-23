module Api
  module V1
    class GovernmentEntitiesController < ApplicationController
      def index
        entities = GovernmentEntity.order(:canonical_name)
        render json: entities.select(:id, :canonical_name, :org_id_infobase)
      end

      def show
        entity = GovernmentEntity.find(params[:id])

        render json: {
          government_entity: entity.as_json(only: [:id, :canonical_name, :org_id_infobase]),
          aliases: entity.government_entity_aliases.as_json(only: [:alias_name, :valid_from, :valid_to]),
          fiscal_authorities: entity.fiscal_authorities.order(:fiscal_year, :document_type).as_json(
            only: [:fiscal_year, :document_type, :vote_number, :vote_type, :description, :amount]
          ),
          fiscal_expenditures: entity.fiscal_expenditures.order(:fiscal_year).as_json(
            only: [:fiscal_year, :vote_number, :vote_type, :description, :pa_voted_ceiling, :actual_expenditure]
          )
        }
      end
    end
  end
end
