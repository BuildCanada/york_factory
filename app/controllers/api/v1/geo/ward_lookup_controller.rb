module Api
  module V1
    module Geo
      # "Find your ward": a postal code in, the ward that contains it out.
      #
      # Public and unauthenticated, like the rest of this namespace. Every
      # answer is a 200 — a postal code we cannot place is a result, not an
      # error — so 400 is reserved for a request we cannot act on at all.
      class WardLookupController < ApplicationController
        def show
          return render_error("postal_code is required") if params[:postal_code].blank?

          boundary_type = params[:boundary_type].presence || ::Warehouse::BoundaryLookup::DEFAULT_BOUNDARY_TYPE
          unless ::Warehouse::GeoBoundary::BOUNDARY_TYPES.include?(boundary_type)
            return render_error("Unknown boundary_type: #{boundary_type}")
          end

          result = ::Warehouse::BoundaryLookup.new(boundary_type: boundary_type).check(params[:postal_code])

          set_cache_headers(result)
          render json: serialize(result)
        end

        private

        def serialize(result)
          {
            postal_code: result.postal_code,
            city: result.city,
            found: result.found?,
            reason: result.reason,
            unverified: result.indeterminate?,
            ward: result.boundary && serialize_ward(result.boundary)
          }
        end

        def serialize_ward(boundary)
          {
            geo_uid: boundary.geo_uid,
            ward_number: boundary.ward_number,
            name_en: boundary.name_en,
            name_fr: boundary.name_fr,
            boundary_type: boundary.boundary_type,
            census_year: boundary.census_year
          }
        end

        # The answer depends only on the postal code, so it caches well. Two
        # exceptions: a missing layer is our outage and must not be cached at
        # all, and an unrecognized code may simply mean the postal import has
        # not run yet, so it gets a short life rather than a day.
        def set_cache_headers(result)
          case result.reason
          when :boundary_data_unavailable
            response.headers["Cache-Control"] = "no-store"
          when :unknown_postal_code
            expires_in 1.hour, public: true
          else
            expires_in 1.day, public: true
          end
        end

        def render_error(message)
          render json: { error: message }, status: :bad_request
        end
      end
    end
  end
end
