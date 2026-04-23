module Api
  module V1
    class MemosController < CmsBaseController
      before_action :authenticate_admin!, only: [ :create, :update, :destroy ]
      before_action :set_memo, only: [ :show, :update, :destroy ]

      def index
        scope = publication_scope
        scope = preview_mode? ? scope : scope.published
        scope = scope.includes(:author, :co_author).with_attached_seo_image.order(published_at: :desc)
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
        Memo.where(publication: params[:publication].presence)
      end

      def memo_params
        params.require(:memo).permit(
          :slug, :author_id, :co_author_id, :author_name, :author_title,
          :author_avatar, :category, :publication, :twitter_embed, :published_at, :featured, :seo_image,
          :title_en, :title_fr,
          :supporters_en, :supporters_fr,
          :body_en, :body_fr, :appendix_en, :appendix_fr,
          key_messages_en: [], key_messages_fr: []
        )
      end

      def serialize_memo(memo, full: false)
        data = {
          id: memo.id,
          slug: memo.slug,
          title: memo.title,
          category: memo.category,
          publication: memo.publication,
          featured: memo.featured,
          published_at: memo.published_at,
          seo_image_url: image_url(memo.seo_image),
          author: memo.author ? { id: memo.author.id, name: memo.author.name, slug: memo.author.slug, profile_photo_url: image_url(memo.author.profile_photo) } : nil
        }

        if full
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
            co_author: memo.co_author ? { id: memo.co_author.id, name: memo.co_author.name, slug: memo.co_author.slug } : nil
          )
        end

        data
      end
    end
  end
end
