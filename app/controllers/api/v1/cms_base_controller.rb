module Api
  module V1
    class CmsBaseController < ApplicationController
      include Localizable
      include Authenticatable
      include Pagy::Method

      private

      def image_url(attachment)
        return nil unless attachment.attached?

        rails_storage_proxy_url(attachment)
      end

      def preview_mode?
        static_preview_token_valid? || doorkeeper_admin_token_valid?
      end

      def static_preview_token_valid?
        params[:preview_token].present? &&
          ENV["DRAFT_MODE_SECRET"].present? &&
          ActiveSupport::SecurityUtils.secure_compare(params[:preview_token], ENV["DRAFT_MODE_SECRET"])
      end

      def doorkeeper_admin_token_valid?
        raw_token = request.headers["Authorization"]&.split(" ", 2)&.last
        return false if raw_token.blank?
        return false if raw_token.include?(".")  # JWTs contain dots; Doorkeeper tokens don't

        token = Doorkeeper::AccessToken.by_token(raw_token)
        token&.accessible? && token.scopes.include?("admin")
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
