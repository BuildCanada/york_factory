module Api
  module V1
    module Kpis
      module Admin
        class BaseController < ApplicationController
          class AmbiguousOrganizationSlug < StandardError
            attr_reader :slug

            def initialize(slug)
              @slug = slug
              super("More than one organization uses slug #{slug.inspect}; pass jurisdiction_slug")
            end
          end

          include Pagy::Method

          before_action :authenticate_api_token!

          rescue_from ActiveRecord::RecordInvalid do |e|
            render json: { error: "validation_failed", details: e.record.errors.full_messages }, status: :unprocessable_entity
          end

          rescue_from ActiveRecord::RecordNotFound do |e|
            render json: { error: "not_found", details: e.message }, status: :not_found
          end

          rescue_from AmbiguousOrganizationSlug do |e|
            render json: {
              error: "ambiguous_organization_slug",
              details: e.message,
              organization_slug: e.slug
            }, status: :bad_request
          end

          private

          def authenticate_api_token!
            raw = request.headers["Authorization"]&.split(" ", 2)&.last
            if (user_api_key = ::ApiKey.authenticate(raw))
              @current_user = user_api_key.user
              return render_forbidden unless @current_user.admin?

              return
            end

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

          def pagy_metadata(pagy)
            { page: pagy.page, pages: pagy.pages, count: pagy.count, per_page: pagy.limit }
          end

          def resolve_organization_by_slug!(slug, jurisdiction_slug: nil)
            if jurisdiction_slug.present?
              jurisdiction = ::Warehouse::Jurisdiction.find_by!(slug: jurisdiction_slug)
              return jurisdiction.organizations.find_by!(slug: slug)
            end

            matches = ::Warehouse::Organization.where(slug: slug).limit(2).to_a
            raise ActiveRecord::RecordNotFound if matches.empty?
            raise AmbiguousOrganizationSlug, slug if matches.length > 1

            matches.first
          end
        end
      end
    end
  end
end
