module Api
  module V1
    module Kpis
      class UnitsController < BaseController
        def index
          units = ::Warehouse::Unit.order(:symbol)
          render json: { data: units.map { |u| serialize_unit(u).merge(notes: u.notes) } }
        end
      end
    end
  end
end
