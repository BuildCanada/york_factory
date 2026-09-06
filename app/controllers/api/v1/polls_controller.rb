module Api
  module V1
    class PollsController < CmsBaseController
      before_action :authenticate_admin!, only: [ :create, :update, :destroy ]
      before_action :set_poll, only: [ :show, :update, :destroy, :download ]

      def index
        scope = Poll.all
        scope = preview_mode? ? scope : scope.published
        scope = scope.includes(:author).with_attached_seo_image.with_attached_banner_image.order(published_at: :desc)
        scope = scope.featured if params[:featured].present?
        scope = scope.search(params[:q]) if params[:q].present?

        pagy, polls = pagy(scope)
        render json: {
          data: polls.map { |m| serialize_poll(m) },
          pagination: pagy_metadata(pagy)
        }
      end

      def show
        render json: serialize_poll(@poll, full: true)
      end

      def download
        name = params[:asset]
        response.headers["Cache-Control"] = "private, no-store"
        if name == "analysis_markdown"
          return send_data @poll.body.to_s, filename: "#{@poll.slug}.md", type: "text/markdown", disposition: "attachment"
        end
        raise ActiveRecord::RecordNotFound unless PollPublication::DOWNLOADS.include?(name)
        attachment = @poll.public_send(name)
        raise ActiveRecord::RecordNotFound unless attachment.attached?

        send_data attachment.download, filename: attachment.filename.to_s,
          type: attachment.content_type, disposition: "attachment"
      end

      def create
        poll = Poll.new(poll_params)
        if poll.save
          render json: serialize_poll(poll, full: true), status: :created
        else
          render json: { errors: poll.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @poll.update(poll_params)
          render json: serialize_poll(@poll, full: true)
        else
          render json: { errors: @poll.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @poll.destroy!
        head :no_content
      end

      private

      def set_poll
        scope = Poll.all
        scope = scope.published unless preview_mode?
        @poll = scope.friendly.find(params[:slug])
      end

      def poll_params
        scalar_fields = [
          *PollPublication::PARAMS,
          :slug, :author_id, :author_name, :author_title,
          :twitter_embed, :featured, :seo_image, :banner_image,
          :title_en, :title_fr,
          :body_en, :body_fr, :appendix_en, :appendix_fr
        ]
        scalar_fields << :published_at unless current_api_key

        params.require(:poll).permit(
          *scalar_fields,
          key_messages_en: [], key_messages_fr: []
        )
      end

      def serialize_poll(poll, full: false)
        data = {
          id: poll.id,
          slug: poll.slug,
          title: poll.title,
          featured: poll.featured,
          published_at: poll.published_at,
          seo_image_url: image_url(poll.seo_image),
          banner_image_url: image_url(poll.banner_image),
          author: poll.author ? { id: poll.author.id, name: poll.author.name, slug: poll.author.slug, profile_photo_url: image_url(poll.author.profile_photo) } : nil
        }

        if full
          data[:poll] = {
            survey_slug: poll.survey_slug, survey_campaign_id: poll.survey_campaign_id,
            pollster: poll.pollster, sample_size: poll.sample_size,
            fieldwork_start: poll.fieldwork_start, fieldwork_end: poll.fieldwork_end,
            methodology: poll.methodology_html, methodology_markdown: poll.methodology,
            news_release: poll.news_release_html, news_release_markdown: poll.news_release,
            downloads: poll.poll_downloads.transform_values { |name|
              download_api_v1_poll_url(poll.slug, asset: name, locale: I18n.locale)
            }
          }
          if preview_mode?
            data[:poll][:launch_copy] = {
              email_subject: poll.email_subject, subscriber_email_markdown: poll.subscriber_email,
              tweet: poll.tweet
            }
          end
          data.merge!(
            body: poll.body_html,
            body_markdown: poll.body,
            appendix: poll.appendix_html,
            appendix_markdown: poll.appendix,
            key_messages: I18n.locale == :fr ? (poll.key_messages_fr.presence || poll.key_messages_en) : poll.key_messages_en,
            twitter_embed: poll.twitter_embed,
            author_name: poll.author_name,
            author_title: poll.author_title
          )
        end

        data
      end
    end
  end
end
