module Api
  module V1
    module Geo
      class AddressesController < ApplicationController
        include Pagy::Method

        def index
          scope = Warehouse::Address.all
          scope = scope.in_province(params[:province_code]) if params[:province_code].present?
          scope = scope.in_postal_code(params[:postal_code]) if params[:postal_code].present?
          scope = scope.in_csd(params[:csd_uid]) if params[:csd_uid].present?
          scope = scope.search_street(params[:street]) if params[:street].present?
          scope = scope.search_city(params[:city]) if params[:city].present?
          scope = scope.order(:province_code, :city, :street_name)

          pagy, addresses = pagy(scope)

          render json: {
            data: addresses.map { |a| serialize_address(a) },
            pagination: {
              page: pagy.page,
              pages: pagy.pages,
              count: pagy.count,
              per_page: pagy.limit
            }
          }
        end

        private

        def serialize_address(address)
          {
            oda_uid: address.oda_uid,
            full_address: address.full_address,
            street_number: address.street_number,
            street_name: address.street_name,
            street_type: address.street_type,
            unit: address.unit,
            city: address.city,
            province_code: address.province_code,
            postal_code: address.postal_code,
            csd_uid: address.csd_uid,
            csd_name: address.csd_name,
            latitude: address.latitude,
            longitude: address.longitude
          }
        end
      end
    end
  end
end
