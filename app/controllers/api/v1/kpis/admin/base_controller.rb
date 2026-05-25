module Api
  module V1
    module Kpis
      module Admin
        class BaseController < ApplicationController
          before_action :authenticate_api_token!

          rescue_from ActiveRecord::RecordInvalid do |e|
            render json: { error: "validation_failed", details: e.record.errors.full_messages }, status: :unprocessable_entity
          end

          rescue_from ActiveRecord::RecordNotFound do |e|
            render json: { error: "not_found", details: e.message }, status: :not_found
          end

          private

          def authenticate_api_token!
            raw = request.headers["Authorization"]&.split(" ", 2)&.last
            @api_token = ::Warehouse::ApiToken.authenticate(raw)
            return render_unauthorized unless @api_token
            render_forbidden unless @api_token.has_scope?("kpis:write")
          end

          def render_unauthorized
            render json: { error: "unauthorized" }, status: :unauthorized
          end

          def render_forbidden
            render json: { error: "forbidden" }, status: :forbidden
          end

          def api_token
            @api_token
          end
        end
      end
    end
  end
end
