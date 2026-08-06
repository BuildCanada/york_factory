module Typesense
  class MultiSearchesController < ApplicationController
    MAX_SEARCHES = 12

    def create
      requests = request_payload.fetch("searches")
      unless requests.is_a?(Array) && requests.length.between?(1, MAX_SEARCHES)
        return render json: { message: "searches must contain between 1 and #{MAX_SEARCHES} requests" },
          status: :bad_request
      end

      searches = requests.map do |search|
        Warehouse::Spending::TypesenseResponse.render(search.to_h)
      rescue Warehouse::Spending::Search::InvalidRequest, ArgumentError => error
        { error: error.message, code: 400 }
      end

      render json: { results: searches }
    rescue ActionController::ParameterMissing, JSON::ParserError, KeyError => error
      render json: { message: error.message }, status: :bad_request
    end

    private

    # typesense-js serializes multi-search as JSON but labels it text/plain, so
    # Rails intentionally does not populate params from the request body.
    def request_payload
      return params.permit!.to_h if params[:searches].present?

      JSON.parse(request.raw_post)
    end
  end
end
