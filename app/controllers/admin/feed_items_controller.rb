module Admin
  class FeedItemsController < BaseController
    before_action :set_feed_item, only: [:show, :edit, :update, :destroy, :retranslate]

    def index
      @pagy, @feed_items = pagy(FeedItem.order(created_at: :desc))
    end

    def show; end
    def new; @feed_item = FeedItem.new; end
    def edit; end

    def create
      @feed_item = FeedItem.new(feed_item_params)
      if @feed_item.save
        redirect_to admin_feed_item_path(@feed_item), notice: "Feed item created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      purge_attachment(:image)
      purge_attachment(:author_photo)
      if @feed_item.update(feed_item_params)
        redirect_to admin_feed_item_path(@feed_item), notice: "Feed item updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @feed_item.destroy!
      redirect_to admin_feed_items_path, notice: "Feed item deleted."
    end

    def retranslate
      @feed_item.update(title_fr: nil, subtitle_fr: nil)
      @feed_item.body_fr = nil
      @feed_item.save!
      TranslateRecordJob.perform_later("FeedItem", @feed_item.id)
      head :ok
    end

    private

    def set_feed_item
      @feed_item = FeedItem.find(params[:id])
    end

    def feed_item_params
      params.require(:feed_item).permit(
        :item_type, :author, :url, :embed_code, :source_url, :featured, :published_at,
        :image, :author_photo,
        :title_en, :title_fr, :subtitle_en, :subtitle_fr,
        :body_en, :body_fr,
        tags: []
      )
    end

    def purge_attachment(name)
      @feed_item.send(name).purge if params.dig(:feed_item, "purge_#{name}") == "1"
    end
  end
end
