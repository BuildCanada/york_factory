module Admin
  class CritiquesController < BaseController
    before_action :set_critique, only: [ :show, :approve, :reject, :destroy ]

    def index
      scope = Critique.includes(:memo).order(created_at: :desc)
      scope = scope.where(status: Critique.statuses[params[:status]]) if Critique.statuses.key?(params[:status])
      @status_filter = params[:status]
      @counts = Critique.group(:status).count
      @pagy, @critiques = pagy(scope)
    end

    def show; end

    def approve
      @critique.approve!(current_user)
      redirect_to admin_critique_path(@critique), notice: "Critique approved."
    end

    def reject
      @critique.reject!(current_user)
      redirect_to admin_critique_path(@critique), notice: "Critique rejected."
    end

    def destroy
      @critique.destroy!
      redirect_to admin_critiques_path, notice: "Critique deleted."
    end

    private

    def set_critique
      @critique = Critique.find(params[:id])
    end
  end
end
