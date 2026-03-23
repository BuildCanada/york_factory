module Api
  module V1
    class BusinessEstablishmentsController < ApplicationController
      def index
        establishments = BusinessEstablishment.all

        establishments = establishments.where(province: params[:province]) if params[:province].present?
        establishments = establishments.where(naics_code: params[:naics]) if params[:naics].present?

        if params[:name].present?
          establishments = establishments.where("business_name ILIKE ?", "%#{params[:name]}%")
        end

        establishments = establishments.order(:business_name).limit([params.fetch(:limit, 100).to_i, 1000].min)

        render json: establishments.select(:id, :business_name, :trade_name, :business_number,
                                            :naics_code, :naics_description, :province, :city)
      end

      def show
        establishment = BusinessEstablishment.find(params[:id])

        render json: {
          business_establishment: establishment.as_json(except: [:raw_data]),
          corporate_entity: establishment.corporate_entity&.as_json(
            only: [:id, :jurisdiction, :registry_id, :legal_name, :status]
          )
        }
      end
    end
  end
end
