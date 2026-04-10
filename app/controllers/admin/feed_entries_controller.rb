module Admin
  class FeedEntriesController < BaseController
    before_action :set_feed_entry, only: [ :edit, :update ]

    def index
      @pagy, @feed_entries = pagy(FeedEntry.chronological.includes(:feedable))
    end

    def edit
    end

    def update
      if @feed_entry.update(feed_entry_params)
        redirect_to admin_feed_entries_path, notice: "Feed entry updated"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_feed_entry
      @feed_entry = FeedEntry.find(params[:id])
    end

    def feed_entry_params
      params.require(:feed_entry).permit(:featured, tags: [])
    end
  end
end
