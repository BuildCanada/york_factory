module Admin
  class PollsController < BaseController
    before_action :set_poll, only: [ :show, :edit, :update, :destroy, :retranslate ]

    def index
      scope = Poll.order(created_at: :desc)
      @pagy, @polls = pagy(scope)
    end

    def import_publication
      upload = params[:publication_export]
      unless upload.respond_to?(:read) && upload.size <= 25.megabytes
        redirect_to admin_polls_path, alert: "Choose a Surveyor publication JSON export smaller than 25 MB."
        return
      end
      poll = Polls::Import.call(JSON.parse(upload.read))
      redirect_to edit_admin_poll_path(poll), notice: "Poll imported as a draft. Review the analysis and crosstabs, then add PDFs and launch copy."
    rescue JSON::ParserError, ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to admin_polls_path, alert: "Import failed: #{e.message}"
    end

    def show; end
    def new; @poll = Poll.new; end
    def edit; end

    def create
      @poll = Poll.new(poll_params)
      if @poll.save
        redirect_to admin_poll_path(@poll), notice: "Poll created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      attributes = poll_params
      # Assign removals as attachment changes so they commit only after a valid
      # save. A replacement upload wins over a checked removal checkbox.
      ([ :seo_image, :banner_image ] + PollPublication::UPLOADS).each do |name|
        attributes[name] = nil if params.dig(:poll, "purge_#{name}") == "1" && attributes[name].blank?
      end
      if @poll.update(attributes)
        redirect_to admin_poll_path(@poll), notice: "Poll updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @poll.destroy!
      redirect_to admin_polls_path, notice: "Poll deleted."
    end

    def retranslate
      @poll.update(title_fr: nil, key_messages_fr: [])
      @poll.body_fr = nil
      @poll.appendix_fr = nil
      @poll.methodology_fr = nil
      @poll.news_release_fr = nil
      @poll.subscriber_email_fr = nil
      @poll.email_subject_fr = nil
      @poll.tweet_fr = nil
      @poll.save!
      TranslateRecordJob.perform_later(@poll)
      head :ok
    end

    private

    def set_poll
      @poll = Poll.friendly.find(params[:id])
    end

    def poll_params
      params.require(:poll).permit(
        *PollPublication::PARAMS,
        :slug, :author_id, :author_name, :author_title,
        :twitter_embed, :published_at, :featured, :seo_image, :banner_image,
        :title_en, :title_fr,
        :body_en, :body_fr, :appendix_en, :appendix_fr,
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
  end
end
