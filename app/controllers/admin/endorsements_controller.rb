module Admin
  class EndorsementsController < BaseController
    before_action :set_endorsement, only: [ :show, :destroy ]

    def index
      scope = Endorsement.includes(:memo, :user).order(created_at: :desc)
      if params[:memo_id].present?
        scope = scope.where(memo_id: params[:memo_id])
        @memo_filter = params[:memo_id]
      end
      @memo_options = Memo.where(id: Endorsement.select(:memo_id)).order(:title_en)
      # pagy already counts the (possibly filtered) scope, so the header total
      # reads off @pagy rather than issuing a second, unfiltered COUNT.
      @pagy, @endorsements = pagy(scope)
    end

    def show; end

    def destroy
      memo_id = @endorsement.memo_id
      # Destroying decrements memos.endorsements_count (counter_cache) and
      # enqueues a RevalidateMemoJob, so the public memo page drops the count too.
      @endorsement.destroy!
      redirect_to admin_endorsements_path(memo_id: memo_id), notice: "Endorsement removed."
    end

    private

    def set_endorsement
      @endorsement = Endorsement.find(params[:id])
    end
  end
end
