module Admin
  class BroadcastBackfillsController < BaseController
    def index
      @requests = BroadcastBackfillRequest.order(created_at: :desc).limit(30)
      scope = Warehouse::MediaStream.where(provider: "cpac", kind: "on_demand").order(Arel.sql("metadata ->> 'provider_published_at' DESC NULLS LAST"), id: :desc)
      if params[:q].present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(500))}%"
        scope = scope.where("title_en ILIKE :query OR title_fr ILIKE :query", query:)
      end
      @pagy, @streams = pagy(:offset, scope, limit: 30)
    end

    def show
      @request = BroadcastBackfillRequest.find(params[:id])
      @pagy, @items = pagy(:offset, @request.items.includes(:media_stream).order(:id), limit: 50)
    end

    def create
      request = BroadcastBackfillRequest.create_for_range!(
        starts_on: params[:starts_on], ends_on: params[:ends_on], mode: params[:mode], requested_by: current_user
      )
      request.enqueue!
      redirect_to admin_broadcast_backfill_path(request), notice: "Historical listing job queued."
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      redirect_to admin_broadcast_backfills_path, alert: error.message
    end

    def queue_stream
      stream = Warehouse::MediaStream.where(provider: "cpac", kind: "on_demand").find(params[:media_stream_id])
      request = BroadcastBackfillRequest.queue_stream!(stream:, requested_by: current_user)
      redirect_to admin_broadcast_backfill_path(request), notice: "Historical capture queued."
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      redirect_to admin_broadcast_backfills_path, alert: error.message
    end

    def retry
      request = BroadcastBackfillRequest.find(params[:id])
      request.retry!
      redirect_to admin_broadcast_backfill_path(request), notice: "Backfill retry queued."
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      redirect_to admin_broadcast_backfills_path, alert: error.message
    end
  end
end
