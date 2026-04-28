module Api
  module V1
    module TradeBarriers
      class ThemesController < CmsBaseController
        def index
          render json: {
            data: ::TradeBarriers::Theme.ordered.map { |t| { id: t.id, name: t.name } }
          }
        end
      end
    end
  end
end
