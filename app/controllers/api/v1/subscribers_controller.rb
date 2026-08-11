module Api
  module V1
    class SubscribersController < CmsBaseController
      def create
        subscriber = Subscriber.new(subscriber_params)
        subscriber.source = "hubspot_form"
        if subscriber.save
          # PostHog: track newsletter subscription (distinct_id is the stable subscriber id, not email)
          PostHog.capture(
            distinct_id: "subscriber_#{subscriber.id}",
            event: "newsletter_subscribed",
            properties: {
              source: subscriber.source,
              placement: subscriber.placement,
              page_name: subscriber.page_name
            }.compact
          )
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
