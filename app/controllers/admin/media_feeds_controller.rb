module Admin
  class MediaFeedsController < BaseController
    before_action :set_feed, only: %i[edit update destroy toggle]

    def index
      @feeds = Warehouse::MediaFeed.alphabetical
    end

    def new
      @feed = Warehouse::MediaFeed.new(enabled: true, cadence_seconds: 300, language: "en")
    end

    def create
      @feed = Warehouse::MediaFeed.new(feed_params)
      if @feed.save
        redirect_to admin_media_feeds_path, notice: "Media feed created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @feed.update(feed_params)
        redirect_to admin_media_feeds_path, notice: "Media feed updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @feed.destroy
        redirect_to admin_media_feeds_path, notice: "Media feed deleted."
      else
        redirect_to admin_media_feeds_path, alert: @feed.errors.full_messages.to_sentence
      end
    end

    def toggle
      @feed.enabled = !@feed.enabled?
      @feed.next_fetch_at = Time.current if @feed.enabled?
      @feed.save!
      redirect_to admin_media_feeds_path, notice: "#{@feed.name} #{@feed.enabled? ? 'enabled' : 'disabled'}."
    end

    private

    def set_feed
      @feed = Warehouse::MediaFeed.find(params[:id])
    end

    def feed_params
      params.require(:media_feed).permit(
        :name, :url, :strategy, :publisher_name, :publisher_domain, :language,
        :cadence_seconds, :fallback_url, :allow_http, :enabled
      )
    end
  end
end
