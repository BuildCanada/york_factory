module Api
  module V1
    class SubscribersController < CmsBaseController
      def create
        subscriber = Subscriber.new(subscriber_params)
        subscriber.source = "hubspot_form"
        if subscriber.save
          render json: { message: "Subscribed" }, status: :created
        else
          render json: { errors: subscriber.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def subscriber_params
        params.require(:subscriber).permit(
          :first_name, :last_name, :email, :postal_code,
          :placement, :page_uri, :page_name, :hubspot_utk, :ip_address
        )
      end
    end
  end
end
