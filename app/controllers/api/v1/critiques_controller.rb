module Api
  module V1
    class CritiquesController < CmsBaseController
      before_action :set_memo

      def index
        scope = @memo.approved_critiques.recent_first
        pagy, critiques = pagy(scope)
        render json: {
          data: critiques.map { |c| serialize(c) },
          pagination: pagy_metadata(pagy)
        }
      end

      def create
        ticket = decoded_ticket
        critique = @memo.critiques.build(
          linkedin_sub:   ticket["sub"],
          name:           ticket["name"],
          given_name:     ticket["given_name"],
          family_name:    ticket["family_name"],
          email:          ticket["email"],
          email_verified: !!ticket["email_verified"],
          picture_url:    ticket["picture"],
          postal_code:    params[:postal_code],
          body:           params[:body]
        )
        if critique.save
          render json: serialize(critique).merge(status: critique.status), status: :created
        else
          render json: { errors: critique.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        existing = @memo.critiques.find_by(linkedin_sub: ticket["sub"])
        render json: { error: "already_submitted", existing: { created_at: existing&.created_at, status: existing&.status } }, status: :conflict
      rescue VerificationTicket::Error => e
        render json: { error: "invalid_ticket", message: e.message }, status: :unauthorized
      end

      private

      def set_memo
        @memo = Memo.friendly.find(params[:memo_slug])
      end

      def decoded_ticket
        token = params[:verified_ticket].to_s
        VerificationTicket.decode(token, expected_kind: "critique", expected_memo_slug: @memo.slug)
      end

      def serialize(c)
        {
          id: c.id,
          name: c.name,
          body: c.body,
          created_at: c.created_at
        }
      end
    end
  end
end
