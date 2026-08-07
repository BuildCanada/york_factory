module Api
  module V1
    class SavedSearchRunsController < ApplicationController
      before_action :authenticate_api_user!

      def index
        saved_search = current_user.saved_searches.find(params[:saved_search_id])
        runs = saved_search.runs.recent_first.limit(100)
        render json: { data: runs.as_json(except: %i[billing performance error], methods: []) }
      end
    end
  end
end
