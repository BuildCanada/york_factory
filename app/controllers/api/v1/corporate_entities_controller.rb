module Api
  module V1
    class CorporateEntitiesController < ApplicationController
      def index
        entities = CorporateEntity.all

        entities = entities.where(jurisdiction: params[:jurisdiction]) if params[:jurisdiction].present?
        entities = entities.where(status: params[:status]) if params[:status].present?
        entities = entities.where(registered_office_province: params[:province]) if params[:province].present?
        entities = entities.where(corporation_type: params[:type]) if params[:type].present?

        if params[:name].present?
          entities = entities.where("legal_name ILIKE ?", "%#{params[:name]}%")
        end

        entities = entities.order(:legal_name).limit([params.fetch(:limit, 100).to_i, 1000].min)

        render json: entities.select(:id, :jurisdiction, :registry_id, :legal_name,
                                      :status, :corporation_type, :registered_office_province)
      end

      def show
        entity = CorporateEntity.find(params[:id])

        render json: {
          corporate_entity: entity.as_json(except: [:raw_data]),
          aliases: entity.corporate_entity_aliases.as_json(only: [:alias_name, :effective_date, :expiry_date]),
          registrations: entity.corporate_registrations.order(:event_date).as_json(
            only: [:event_type, :event_date, :description]
          ),
          government_entity: entity.government_entity&.as_json(only: [:id, :canonical_name])
        }
      end

      def directors
        entity = CorporateEntity.find(params[:id])

        appointments = entity.director_appointments.includes(:corporate_director).map do |appt|
          {
            director: appt.corporate_director.as_json(only: [:id, :full_name, :province]),
            appointed_date: appt.appointed_date,
            ceased_date: appt.ceased_date,
            role: appt.role
          }
        end

        render json: { corporate_entity_id: entity.id, directors: appointments }
      end
    end
  end
end
