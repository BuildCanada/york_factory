module Typesense
  class DocumentsController < ApplicationController
    rescue_from Warehouse::Spending::Search::InvalidRequest, ArgumentError do |error|
      render json: { message: error.message }, status: :bad_request
    end

    def index
      render json: Warehouse::Spending::TypesenseResponse.render(
        params.permit!.to_h.merge("collection" => params[:collection])
      )
    end
  end
end
