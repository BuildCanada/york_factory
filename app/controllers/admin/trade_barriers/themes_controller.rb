module Admin
  module TradeBarriers
    class ThemesController < BaseController
      before_action :set_theme, only: [ :show, :edit, :update, :destroy ]

      def index
        @themes = ::TradeBarriers::Theme.ordered
      end

      def show; end

      def new
        @theme = ::TradeBarriers::Theme.new
      end

      def edit; end

      def create
        @theme = ::TradeBarriers::Theme.new(theme_params)
        if @theme.save
          redirect_to admin_trade_barriers_themes_path, notice: "Theme created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def update
        if @theme.update(theme_params)
          redirect_to admin_trade_barriers_themes_path, notice: "Theme updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @theme.destroy
          redirect_to admin_trade_barriers_themes_path, notice: "Theme deleted."
        else
          redirect_to admin_trade_barriers_themes_path,
            alert: @theme.errors.full_messages.to_sentence
        end
      end

      private

      def set_theme
        @theme = ::TradeBarriers::Theme.find(params[:id])
      end

      def theme_params
        params.require(:trade_barriers_theme).permit(:name)
      end
    end
  end
end
