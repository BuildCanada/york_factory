module Admin
  class PostsController < BaseController
    before_action :set_post, only: [ :show, :edit, :update, :destroy, :retranslate ]

    def index
      @pagy, @posts = pagy(Post.order(created_at: :desc))
    end

    def show; end
    def new; @post = Post.new; end
    def edit; end

    def create
      @post = Post.new(post_params)
      if @post.save
        redirect_to admin_post_path(@post), notice: "Post created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      purge_attachment(:seo_image)
      purge_attachment(:banner_image)
      if @post.update(post_params)
        redirect_to admin_post_path(@post), notice: "Post updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @post.destroy!
      redirect_to admin_posts_path, notice: "Post deleted."
    end

    def retranslate
      @post.update(summary_fr: nil, title_fr: nil)
      @post.body_fr = nil
      @post.save!
      TranslateRecordJob.perform_later(@post)
      head :ok
    end

    private

    def set_post
      @post = Post.friendly.find(params[:id])
    end

    def post_params
      params.require(:post).permit(
        :hidden, :published_at, :seo_image, :banner_image,
        :title_en, :title_fr, :summary_en, :summary_fr,
        :body_en, :body_fr
      )
    end

    def purge_attachment(name)
      @post.send(name).purge if params.dig(:post, "purge_#{name}") == "1"
    end
  end
end
