module Api
  module V1
    class FeedItemsController < CmsBaseController
      before_action :authenticate_admin!, only: [ :create, :update, :destroy ]
      before_action :set_feed_item, only: [ :show, :update, :destroy ]

      def index
        scope = preview_mode? ? FeedItem.all : FeedItem.published
        scope = scope.with_attached_image.order(created_at: :desc)
        scope = scope.by_type(params[:type]) if params[:type].present?
        scope = scope.featured if params[:featured].present?

        pagy, items = pagy(scope)
        render json: {
          data: items.map { |fi| serialize_feed_item(fi) },
          pagination: pagy_metadata(pagy)
        }
      end

      def show
        render json: serialize_feed_item(@feed_item, full: true)
      end

      def create
        item = FeedItem.new(feed_item_params)
        if item.save
          render json: serialize_feed_item(item, full: true), status: :created
        else
          render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @feed_item.update(feed_item_params)
          render json: serialize_feed_item(@feed_item, full: true)
        else
          render json: { errors: @feed_item.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @feed_item.destroy!
        head :no_content
      end

      private

      def set_feed_item
        @feed_item = FeedItem.find(params[:id])
      end

      def feed_item_params
        params.require(:feed_item).permit(
          :item_type, :author, :url, :embed_code, :source_url, :featured,
          :image, :author_photo,
          :title_en, :title_fr, :subtitle_en, :subtitle_fr,
          :body_en, :body_fr,
          tags: []
        )
      end

      def serialize_feed_item(item, full: false)
        data = {
          id: item.id,
          item_type: item.item_type,
          title: item.title,
          subtitle: item.subtitle,
          author: item.author,
          url: item.url,
          featured: item.featured,
          tags: item.tags,
          image_url: image_url(item.image)
        }
        if full
          data[:body] = item.body.to_s
          data[:embed_code] = item.embed_code
          data[:source_url] = item.source_url
          data[:author_photo_url] = image_url(item.author_photo)
        end
        data
      end
    end
  end
end
