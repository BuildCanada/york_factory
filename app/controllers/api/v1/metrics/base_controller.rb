module Api
  module V1
    module Metrics
      class BaseController < ApplicationController
        before_action :authenticate_admin_api_key!

        private

        def authenticate_admin_api_key!
          api_key = current_api_key
          return render_unauthorized unless api_key

          @current_user = api_key.user
          render_forbidden unless @current_user.admin?
        end
      end
    end
  end
end
