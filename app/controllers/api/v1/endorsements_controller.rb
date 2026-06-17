module Api
  module V1
    class EndorsementsController < CmsBaseController
      before_action :set_memo

      def index
        scope = @memo.endorsements.order(created_at: :desc)
        pagy, endorsements = pagy(scope)
        render json: {
          data: endorsements.map { |e| serialize(e) },
          pagination: pagy_metadata(pagy)
        }
      end

      def create
        ticket = decoded_ticket
        endorsement = @memo.endorsements.build(
          linkedin_sub:   ticket["sub"],
          name:           ticket["name"],
          given_name:     ticket["given_name"],
          family_name:    ticket["family_name"],
          email:          ticket["email"],
          email_verified: !!ticket["email_verified"],
          picture_url:    ticket["picture"],
          postal_code:    params[:postal_code]
        )
        if endorsement.save
          render json: serialize(endorsement), status: :created
        else
          render json: { errors: endorsement.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        existing = @memo.endorsements.find_by(linkedin_sub: ticket["sub"])
        render json: { error: "already_submitted", existing: { created_at: existing&.created_at } }, status: :conflict
      rescue VerificationTicket::Error => e
        render json: { error: "invalid_ticket", message: e.message }, status: :unauthorized
      end

      private

      def set_memo
        @memo = Memo.friendly.find(params[:memo_slug])
      end

      def decoded_ticket
        token = params[:verified_ticket].to_s
        VerificationTicket.decode(token, expected_kind: "endorsement", expected_memo_slug: @memo.slug)
      end

      def serialize(e)
        {
          id: e.id,
          name: e.name,
          created_at: e.created_at
        }
      end
    end
  end
end
