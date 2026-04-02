module Api
  module V1
    class CmsBaseController < ApplicationController
      include Localizable
      include Authenticatable
      include Pagy::Backend

      private

      def preview_mode?
        params[:preview_token].present? &&
          ENV["DRAFT_MODE_SECRET"].present? &&
          ActiveSupport::SecurityUtils.secure_compare(params[:preview_token], ENV["DRAFT_MODE_SECRET"])
      end

      def pagy_metadata(pagy)
        {
          page: pagy.page,
          pages: pagy.pages,
          count: pagy.count,
          per_page: pagy.limit
        }
      end
    end
  end
end
