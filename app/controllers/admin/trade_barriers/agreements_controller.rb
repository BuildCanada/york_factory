module Admin
  module TradeBarriers
    class AgreementsController < BaseController
      before_action :set_agreement, only: [ :show, :edit, :update, :destroy ]

      def index
        @agreements = ::TradeBarriers::Agreement.includes(:theme).recent
      end

      def show; end

      def new
        @agreement = ::TradeBarriers::Agreement.new
        prefill_jurisdictions(@agreement)
      end

      def edit
        prefill_jurisdictions(@agreement)
      end

      def create
        @agreement = ::TradeBarriers::Agreement.new(agreement_params)
        if @agreement.save
          redirect_to admin_trade_barriers_agreement_path(@agreement),
            notice: "Agreement created."
        else
          prefill_jurisdictions(@agreement)
          render :new, status: :unprocessable_entity
        end
      end

      def update
        if @agreement.update(agreement_params)
          redirect_to admin_trade_barriers_agreement_path(@agreement),
            notice: "Agreement updated."
        else
          prefill_jurisdictions(@agreement)
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @agreement.destroy!
        redirect_to admin_trade_barriers_agreements_path,
          notice: "Agreement deleted."
      end

      private

      def set_agreement
        @agreement = ::TradeBarriers::Agreement.friendly.find(params[:id])
      end

      def prefill_jurisdictions(agreement)
        existing = agreement.agreement_jurisdictions.index_by(&:jurisdiction_id)
        ::Warehouse::Jurisdiction.order(:name).each do |jurisdiction|
          next if existing.key?(jurisdiction.id)
          agreement.agreement_jurisdictions.build(
            jurisdiction: jurisdiction,
            status: "unknown"
          )
        end
      end

      def agreement_params
        params.require(:trade_barriers_agreement).permit(
          :title, :summary, :description, :status,
          :deadline, :launch_date, :source_url, :theme_id,
          agreement_jurisdictions_attributes: [
            :id, :jurisdiction_id, :status, :notes, :_destroy
          ],
          histories_attributes: [
            :id, :status, :date_entered, :_destroy
          ]
        )
      end
    end
  end
end
