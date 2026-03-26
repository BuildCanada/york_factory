module Admin
  class SubscribersController < BaseController
    def index
      scope = Subscriber.order(created_at: :desc)
      scope = scope.where("email ILIKE ?", "%#{params[:q]}%") if params[:q].present?
      @pagy, @subscribers = pagy(scope)
    end
  end
end
