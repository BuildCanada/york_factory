module Admin
  class FaqsController < BaseController
    before_action :set_faq, only: [:show, :edit, :update, :destroy, :retranslate]

    def index
      @faqs = Faq.ordered
    end

    def show; end
    def new; @faq = Faq.new; end
    def edit; end

    def create
      @faq = Faq.new(faq_params)
      if @faq.save
        redirect_to admin_faq_path(@faq), notice: "FAQ created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @faq.update(faq_params)
        redirect_to admin_faq_path(@faq), notice: "FAQ updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @faq.destroy!
      redirect_to admin_faqs_path, notice: "FAQ deleted."
    end

    def reorder
      params[:ordered_ids].each_with_index do |id, index|
        Faq.where(id: id).update_all(position: index)
      end
      head :ok
    end

    def retranslate
      @faq.update(question_fr: nil, answer_text_fr: nil)
      @faq.answer_fr = nil
      @faq.save!
      TranslateRecordJob.perform_later("Faq", @faq.id)
      head :ok
    end

    private

    def set_faq
      @faq = Faq.find(params[:id])
    end

    def faq_params
      params.require(:faq).permit(
        :link_text, :link_href, :position, :published_at,
        :question_en, :question_fr, :answer_text_en, :answer_text_fr,
        :answer_en, :answer_fr
      )
    end
  end
end
