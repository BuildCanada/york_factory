module Api
  module V1
    class FaqsController < CmsBaseController
      before_action :authenticate_admin!, only: [:create, :update, :destroy, :bulk_update]
      before_action :set_faq, only: [:update, :destroy]

      def index
        scope = preview_mode? ? Faq.all : Faq.published
        render json: {
          data: scope.ordered.map { |f| serialize_faq(f) }
        }
      end

      def create
        faq = Faq.new(faq_params)
        if faq.save
          render json: serialize_faq(faq), status: :created
        else
          render json: { errors: faq.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @faq.update(faq_params)
          render json: serialize_faq(@faq)
        else
          render json: { errors: @faq.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def bulk_update
        ActiveRecord::Base.transaction do
          updates = params.require(:faqs)
          updates.each do |entry|
            faq = Faq.find(entry[:id])
            faq.update!(entry.permit(:position, :link_text, :link_href, :question_en, :question_fr, :answer_text_en, :answer_text_fr))
          end
        end
        render json: { message: "Updated" }
      end

      def destroy
        @faq.destroy!
        head :no_content
      end

      private

      def set_faq
        @faq = Faq.find(params[:id])
      end

      def faq_params
        params.require(:faq).permit(
          :link_text, :link_href, :position,
          :question_en, :question_fr, :answer_text_en, :answer_text_fr,
          :answer_en, :answer_fr
        )
      end

      def serialize_faq(faq)
        {
          id: faq.id,
          question: faq.question,
          answer: faq.answer.to_s,
          answer_text: faq.answer_text,
          link_text: faq.link_text,
          link_href: faq.link_href,
          position: faq.position
        }
      end

    end
  end
end
