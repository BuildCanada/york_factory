module Api
  module V1
    class SavedSearchMatchesController < ApplicationController
      before_action :authenticate_api_user!

      def index
        saved_search = current_user.saved_searches.find(params[:saved_search_id])
        matches = saved_search.matches.includes(:searchable).order(matched_at: :desc).limit(100)
        render json: {
          data: matches.map do |match|
            data = match.searchable.search_data.to_h.deep_symbolize_keys
            {
              id: match.id,
              searchable_type: match.searchable_type,
              searchable_id: match.searchable_id,
              title: data[:title],
              url: data[:canonical_url],
              searchable_revision: match.searchable_revision,
              matched_at: match.matched_at,
              evidence: match.match_evidence,
              state: match.state
            }
          end
        }
      end
    end
  end
end
