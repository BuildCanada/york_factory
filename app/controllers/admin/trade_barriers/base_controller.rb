module Admin
  module TradeBarriers
    class BaseController < ::Admin::BaseController
      skip_before_action :require_admin!
      before_action :require_trade_barriers_editor!

      private

      def require_trade_barriers_editor!
        unless user_signed_in?
          redirect_to new_user_session_path and return
        end

        unless current_user.can_edit_trade_barriers?
          redirect_to new_user_session_path, alert: "Not authorized."
        end
      end
    end
  end
end
