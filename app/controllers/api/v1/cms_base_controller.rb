module Api
  module V1
    class CmsBaseController < ApplicationController
      include Localizable
      include Pagy::Method

      private

      def image_url(attachment)
        return nil unless attachment.attached?

        rails_storage_proxy_url(attachment)
      end

      def preview_mode?
        current_api_key&.user&.admin? || doorkeeper_admin_token_valid?
      end

      def doorkeeper_admin_token_valid?
        # doorkeeper_token extracts the bearer token from the request and looks it
        # up, returning nil for anything that isn't a live Doorkeeper token (a
        # devise JWT, an expired/revoked token, or no token at all).
        token = doorkeeper_token
        return false unless token&.accessible?

        # Any user can hold a token (general login), so preview access is gated on
        # the token owner actually being an admin — never on the client's request.
        User.find_by(id: token.resource_owner_id)&.admin? || false
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
