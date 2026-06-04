module Api
  module V1
    module Kpis
      class BaseController < ApplicationController
        class AmbiguousOrganizationSlug < StandardError
          attr_reader :slug

          def initialize(slug)
            @slug = slug
            super("More than one organization uses slug #{slug.inspect}; pass jurisdiction_slug")
          end
        end

        include Pagy::Method

        rescue_from ActiveRecord::RecordNotFound do |_e|
          render json: { error: "Not found" }, status: :not_found
        end

        rescue_from AmbiguousOrganizationSlug do |e|
          render json: {
            error: "ambiguous_organization_slug",
            details: e.message,
            organization_slug: e.slug
          }, status: :bad_request
        end

        private

        def pagy_metadata(pagy)
          { page: pagy.page, pages: pagy.pages, count: pagy.count, per_page: pagy.limit }
        end

        def serialize_unit(unit)
          {
            id: unit.id,
            symbol: unit.symbol,
            kind: unit.kind,
            base_unit: unit.base_unit,
            scale: unit.scale,
            currency_code: unit.currency_code,
            denominator_unit: unit.denominator_unit,
            denominator_scale: unit.denominator_scale
          }
        end

        def serialize_organization_summary(org)
          {
            id: org.id,
            slug: org.slug,
            canonical_name: org.canonical_name,
            active_from_year: org.active_from_year,
            active_to_year: org.active_to_year
          }
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
