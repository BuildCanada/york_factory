module Admin
  class MemosController < BaseController
    before_action :set_memo, only: [ :show, :edit, :update, :destroy, :retranslate ]

    def index
      scope = Memo.order(created_at: :desc)
      scope = scope.by_publication(params[:publication]) if params[:publication].present?
      @publication_filter = params[:publication]
      @pagy, @memos = pagy(scope)
    end

    def import_poll
      upload = params[:publication_export]
      unless upload.respond_to?(:read) && upload.size <= 25.megabytes
        redirect_to admin_memos_path, alert: "Choose a Surveyor publication JSON export smaller than 25 MB."
        return
      end
      memo = Polls::Import.call(JSON.parse(upload.read))
      redirect_to edit_admin_memo_path(memo), notice: "Poll imported as a draft. Review the analysis and crosstabs, then add PDFs and launch copy."
    rescue JSON::ParserError, ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to admin_memos_path, alert: "Import failed: #{e.message}"
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
      purge_attachment(:banner_image)
      PollPublication::DOWNLOADS.each { |name| purge_attachment(name) }
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
      @memo.methodology_fr = nil
      @memo.news_release_fr = nil
      @memo.subscriber_email_fr = nil
      @memo.email_subject_fr = nil
      @memo.tweet_fr = nil
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
        *PollPublication::PARAMS,
        :slug, :author_id, :co_author_id, :author_name, :author_title,
        :author_avatar, :category, :publication, :twitter_embed, :published_at, :featured, :seo_image, :banner_image,
        :title_en, :title_fr,
        :body_en, :body_fr, :appendix_en, :appendix_fr,
        :supporters_en, :supporters_fr,
        key_messages_en: [], key_messages_fr: []
      ).tap do |p|
        p[:key_messages_en] = normalize_key_messages(p[:key_messages_en]) if p.key?(:key_messages_en)
        p[:key_messages_fr] = normalize_key_messages(p[:key_messages_fr]) if p.key?(:key_messages_fr)
      end
    end

    def normalize_key_messages(values)
      Array(values).filter_map do |v|
        str = v.is_a?(Hash) ? (v["message"] || v[:message]) : v
        { "message" => str.to_s.strip } if str.to_s.strip.present?
      end
    end

    def purge_attachment(name)
      @memo.send(name).purge if params.dig(:memo, "purge_#{name}") == "1"
    end
  end
end
