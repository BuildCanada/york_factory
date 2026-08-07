module Api
  module V1
    class CritiquesController < CmsBaseController
      include EngagementAuthorization

      before_action :authenticate_api_user!, only: :create
      before_action :set_memo
      before_action :require_postal_code!, only: :create

      def index
        scope = @memo.approved_critiques.includes(:user).recent_first
        pagy, critiques = pagy(scope)
        render json: {
          data: critiques.map { |c| serialize(c) },
          pagination: pagy_metadata(pagy)
        }
      end

      def create
        critique = @memo.critiques.build(user: engagement_user, body: params[:body])
        if critique.save
          # PostHog: track memo critique submission
          PostHog.capture(
            distinct_id: engagement_user.posthog_distinct_id,
            event: "memo_critiqued",
            properties: {
              memo_slug: @memo.slug,
              memo_title: @memo.title,
              memo_category: @memo.category
            }
          )
          render json: serialize(critique).merge(status: critique.status), status: :created
        elsif critique.errors.of_kind?(:user_id, :taken)
          render_already_submitted
        else
          render json: { errors: critique.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        render_already_submitted
      end

      private

      def set_memo
        @memo = Memo.friendly.find(params[:memo_slug])
      end

      def render_already_submitted
        existing = @memo.critiques.find_by(user_id: engagement_user.id)
        render json: { error: "already_submitted", existing: { created_at: existing&.created_at, status: existing&.status } }, status: :conflict
      end

      def serialize(critique)
        {
          id: critique.id,
          name: critique.author_name,
          body: critique.body,
          created_at: critique.created_at
        }
      end
    end
  end
end
