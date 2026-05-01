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
        preview_user&.admin? == true
      end

      def preview_user
        return @preview_user if defined?(@preview_user)

        token = params[:preview_token].presence || request.headers["Authorization"]&.split(" ")&.last
        return @preview_user = nil if token.blank?

        begin
          payload = JWT.decode(token, devise_jwt_secret, true, algorithm: "HS256").first
          return @preview_user = nil if JwtDenylist.exists?(jti: payload["jti"])
          @preview_user = User.find(payload["sub"])
        rescue JWT::DecodeError, ActiveRecord::RecordNotFound
          @preview_user = nil
        end
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
