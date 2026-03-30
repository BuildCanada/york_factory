module Admin
  class MemosController < BaseController
    before_action :set_memo, only: [ :show, :edit, :update, :destroy, :retranslate ]

    def index
      @pagy, @memos = pagy(Memo.order(created_at: :desc))
    end

    def show; end
    def new; @memo = Memo.new; end
    def edit; end

    def create
      @memo = Memo.new(memo_params)
      if @memo.save
        redirect_to admin_memo_path(@memo), notice: "Memo created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      purge_attachment(:seo_image)
      if @memo.update(memo_params)
        redirect_to admin_memo_path(@memo), notice: "Memo updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @memo.destroy!
      redirect_to admin_memos_path, notice: "Memo deleted."
    end

    def retranslate
      @memo.update(title_fr: nil, key_messages_fr: [])
      @memo.body_fr = nil
      @memo.appendix_fr = nil
      @memo.supporters_fr = nil
      @memo.save!
      TranslateRecordJob.perform_later(@memo)
      head :ok
    end

    private

    def set_memo
      @memo = Memo.friendly.find(params[:id])
    end

    def memo_params
      params.require(:memo).permit(
        :slug, :author_id, :co_author_id, :author_name, :author_title,
        :author_avatar, :category, :twitter_embed, :published_at, :featured, :seo_image,
        :title_en, :title_fr,
        :body_en, :body_fr, :appendix_en, :appendix_fr,
        :supporters_en, :supporters_fr,
        key_messages: []
      )
    end

    def purge_attachment(name)
      @memo.send(name).purge if params.dig(:memo, "purge_#{name}") == "1"
    end
  end
end
