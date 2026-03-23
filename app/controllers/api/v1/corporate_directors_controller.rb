module Api
  module V1
    class CorporateDirectorsController < ApplicationController
      def entities
        director = CorporateDirector.find(params[:id])

        appointments = director.director_appointments.includes(:corporate_entity).map do |appt|
          {
            corporate_entity: appt.corporate_entity.as_json(
              only: [:id, :jurisdiction, :registry_id, :legal_name, :status]
            ),
            appointed_date: appt.appointed_date,
            ceased_date: appt.ceased_date,
            role: appt.role
          }
        end

        render json: { director: director.as_json(only: [:id, :full_name]), entities: appointments }
      end
    end
  end
end
