module Api
  module V1
    module Spending
      class AwardsController < ApplicationController
        def show
          award = find_award
          return render json: { error: "Not found" }, status: :not_found unless award

          render json: { data: ::Warehouse::Spending::Serializer.normalized(award) }
        end

        private

        def find_award
          scope = ::Warehouse::SpendingAward.published.includes(:source)
          if params[:database].present?
            scope.joins(:source).merge(::Warehouse::Source.where(name: params[:database]))
              .find_by(external_key: params[:id])
          elsif params[:id].to_s.include?(":")
            award = ::Warehouse::SpendingAward.find_by_search_id(params[:id])
            award if award&.published?
          else
            scope.find_by(id: params[:id]) || scope.find_by(external_key: params[:id])
          end
        end
      end
    end
  end
end
