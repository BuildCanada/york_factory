module Api
  module V1
    class MemosController < CmsBaseController
      before_action :authenticate_admin!, only: [ :create, :update, :destroy ]
      before_action :set_memo, only: [ :show, :update, :destroy, :download ]

      def index
        scope = publication_scope
        scope = preview_mode? ? scope : scope.published
        scope = scope.includes(:author, :co_author).with_attached_seo_image.with_attached_banner_image.order(published_at: :desc)
        scope = scope.where(content_kind: params[:content_kind]) if params[:content_kind].present?
        scope = scope.featured if params[:featured].present?
        scope = scope.by_category(params[:category]) if params[:category].present?
        scope = scope.search(params[:q]) if params[:q].present?

        pagy, memos = pagy(scope)
        render json: {
          data: memos.map { |m| serialize_memo(m) },
          pagination: pagy_metadata(pagy)
        }
      end

      def show
        render json: serialize_memo(@memo, full: true)
      end

      def download
        name = params[:asset]
        raise ActiveRecord::RecordNotFound unless @memo.poll?
        response.headers["Cache-Control"] = "private, no-store"
        if name == "analysis_markdown"
          return send_data @memo.body.to_s, filename: "#{@memo.slug}.md", type: "text/markdown", disposition: "attachment"
        end
        raise ActiveRecord::RecordNotFound unless PollPublication::DOWNLOADS.include?(name)
        attachment = @memo.public_send(name)
        raise ActiveRecord::RecordNotFound unless attachment.attached?

        send_data attachment.download, filename: attachment.filename.to_s,
          type: attachment.content_type, disposition: "attachment"
      end

      def create
        memo = Memo.new(memo_params)
        if memo.save
          render json: serialize_memo(memo, full: true), status: :created
        else
          render json: { errors: memo.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @memo.update(memo_params)
          render json: serialize_memo(@memo, full: true)
        else
          render json: { errors: @memo.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @memo.destroy!
        head :no_content
      end

      private

      def set_memo
        scope = publication_scope
        scope = scope.published unless preview_mode?
        @memo = scope.friendly.find(params[:slug])
      end

      def publication_scope
        Memo.where(publication: params[:publication].presence || Memo::DEFAULT_PUBLICATION)
      end

      def memo_params
        scalar_fields = [
          *PollPublication::PARAMS,
          :slug, :author_id, :co_author_id, :author_name, :author_title,
          :author_avatar, :category, :publication, :twitter_embed, :featured, :seo_image, :banner_image,
          :title_en, :title_fr,
          :supporters_en, :supporters_fr,
          :body_en, :body_fr, :appendix_en, :appendix_fr
        ]
        scalar_fields << :published_at unless current_api_key

        params.require(:memo).permit(
          *scalar_fields,
          key_messages_en: [], key_messages_fr: []
        )
      end

      def serialize_memo(memo, full: false)
        data = {
          id: memo.id,
          slug: memo.slug,
          title: memo.title,
          category: memo.category,
          content_kind: memo.content_kind,
          publication: memo.publication,
          featured: memo.featured,
          published_at: memo.published_at,
          seo_image_url: image_url(memo.seo_image),
          banner_image_url: image_url(memo.banner_image),
          author: memo.author ? { id: memo.author.id, name: memo.author.name, slug: memo.author.slug, profile_photo_url: image_url(memo.author.profile_photo) } : nil
        }

        if full
          if memo.poll?
            data[:poll] = {
              survey_slug: memo.survey_slug, survey_campaign_id: memo.survey_campaign_id,
              pollster: memo.pollster, sample_size: memo.sample_size,
              fieldwork_start: memo.fieldwork_start, fieldwork_end: memo.fieldwork_end,
              methodology: memo.methodology_html, methodology_markdown: memo.methodology,
              news_release: memo.news_release_html, news_release_markdown: memo.news_release,
              downloads: memo.poll_downloads.transform_values { |name|
                download_api_v1_memo_url(memo.slug, asset: name, publication: memo.publication, locale: I18n.locale)
              }
            }
            if preview_mode?
              data[:poll][:launch_copy] = {
                email_subject: memo.email_subject, subscriber_email_markdown: memo.subscriber_email,
                tweet: memo.tweet
              }
            end
          end
          data.merge!(
            body: memo.body_html,
            body_markdown: memo.body,
            appendix: memo.appendix_html,
            appendix_markdown: memo.appendix,
            supporters: memo.supporters_html,
            supporters_markdown: memo.supporters,
            key_messages: I18n.locale == :fr ? (memo.key_messages_fr.presence || memo.key_messages_en) : memo.key_messages_en,
            twitter_embed: memo.twitter_embed,
            author_name: memo.author_name,
            author_title: memo.author_title,
            co_author: memo.co_author ? { id: memo.co_author.id, name: memo.co_author.name, slug: memo.co_author.slug } : nil,
            endorsements_count: memo.endorsements_count,
            critiques_count: memo.approved_critiques_count,
            recent_endorsers: memo.endorsements.joins(:user).order(created_at: :desc).limit(5)
              .pluck("users.name", :created_at).map { |n, t| { name: n, created_at: t } },
            critiques: memo.approved_critiques.joins(:user).order(created_at: :desc).limit(20)
              .pluck(:id, "users.name", :body, :created_at)
              .map { |id, name, body, t| { id: id, name: name, body: body, created_at: t } }
          )
        end

        data
      end
    end
  end
end
