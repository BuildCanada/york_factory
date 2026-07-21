module Api
  module V1
    class EndorsementsController < CmsBaseController
      include EngagementAuthorization

      before_action :doorkeeper_authorize!, only: :create
      before_action :set_memo
      before_action :require_postal_code!, only: :create

      def index
        scope = @memo.endorsements.includes(:user).order(created_at: :desc)
        pagy, endorsements = pagy(scope)
        render json: {
          data: endorsements.map { |e| serialize(e) },
          pagination: pagy_metadata(pagy)
        }
      end

      def create
        endorsement = @memo.endorsements.build(user: engagement_user)
        if endorsement.save
          render json: serialize(endorsement), status: :created
        elsif endorsement.errors.of_kind?(:user_id, :taken)
          render_already_submitted
        else
          render json: { errors: endorsement.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        render_already_submitted
      end

      private

      def set_memo
        @memo = Memo.friendly.find(params[:memo_slug])
      end

      def render_already_submitted
        existing = @memo.endorsements.find_by(user_id: engagement_user.id)
        render json: { error: "already_submitted", existing: { created_at: existing&.created_at } }, status: :conflict
      end

      def serialize(endorsement)
        {
          id: endorsement.id,
          name: endorsement.author_name,
          created_at: endorsement.created_at
        }
      end
    end
  end
end
