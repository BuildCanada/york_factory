module Api
  module V1
    module Warehouse
      class JurisdictionsController < CmsBaseController
        def index
          render json: {
            data: ::Warehouse::Jurisdiction.order(:name).map do |j|
              { id: j.id, name: j.name, code: j.code, level: j.level }
            end
          }
        end
      end
    end
  end
end
