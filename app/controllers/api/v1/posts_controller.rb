module Api
  module V1
    class PostsController < CmsBaseController
      before_action :authenticate_admin!, only: [ :create, :update, :destroy ]
      before_action :set_post, only: [ :show, :update, :destroy ]

      def index
        scope = (params[:hidden].present? && current_user&.admin?) ? Post.all : Post.visible
        scope = preview_mode? ? scope : scope.published
        scope = scope.with_attached_seo_image.order(published_at: :desc)

        pagy, posts = pagy(scope)
        render json: {
          data: posts.map { |p| serialize_post(p) },
          pagination: pagy_metadata(pagy)
        }
      end

      def show
        render json: serialize_post(@post, full: true)
      end

      def create
        post = Post.new(post_params)
        if post.save
          render json: serialize_post(post, full: true), status: :created
        else
          render json: { errors: post.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @post.update(post_params)
          render json: serialize_post(@post, full: true)
        else
          render json: { errors: @post.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @post.destroy!
        head :no_content
      end

      private

      def set_post
        scope = preview_mode? ? Post.all : Post.published
        @post = scope.friendly.find(params[:slug])
      end

      def post_params
        params.require(:post).permit(
          :hidden, :published_at, :seo_image,
          :title_en, :title_fr, :summary_en, :summary_fr,
          :body_en, :body_fr
        )
      end

      def serialize_post(post, full: false)
        data = {
          id: post.id,
          slug: post.slug,
          title: post.title,
          summary: post.summary,
          published_at: post.published_at,
          seo_image_url: image_url(post.seo_image)
        }
        data[:body] = post.body.to_s if full
        data
      end
    end
  end
end
