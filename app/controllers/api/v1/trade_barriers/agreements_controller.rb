module Api
  module V1
    module TradeBarriers
      class AgreementsController < CmsBaseController
        def index
          agreements = ::TradeBarriers::Agreement
            .includes(:theme, agreement_jurisdictions: [ :jurisdiction, :histories ], histories: [])
            .recent
          render json: { data: agreements.map { |a| serialize_agreement(a, detail: false) } }
        end

        def show
          agreement = ::TradeBarriers::Agreement
            .includes(:theme, agreement_jurisdictions: [ :jurisdiction, :histories ], histories: [])
            .friendly
            .find(params[:slug])
          render json: serialize_agreement(agreement, detail: true)
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Not found" }, status: :not_found
        end

        private

        def serialize_agreement(agreement, detail:)
          base = {
            id: agreement.id,
            slug: agreement.slug,
            title: agreement.title,
            summary: agreement.summary,
            status: agreement.status,
            theme: agreement.theme && { id: agreement.theme.id, name: agreement.theme.name },
            deadline: agreement.deadline,
            launch_date: agreement.launch_date,
            source_url: agreement.source_url,
            jurisdictions: agreement.agreement_jurisdictions.map { |aj| serialize_jurisdiction(aj, detail: detail) },
            history: agreement.histories.map { |h| { status: h.status, date_entered: h.date_entered } },
            updated_at: agreement.updated_at
          }
          base[:description] = agreement.description if detail
          base
        end

        def serialize_jurisdiction(agreement_jurisdiction, detail:)
          base = {
            id: agreement_jurisdiction.jurisdiction.id,
            name: agreement_jurisdiction.jurisdiction.name,
            code: agreement_jurisdiction.jurisdiction.code,
            level: agreement_jurisdiction.jurisdiction.level,
            status: agreement_jurisdiction.status,
            notes: agreement_jurisdiction.notes
          }
          if detail
            base[:history] = agreement_jurisdiction.histories.map do |h|
              { status: h.status, date_entered: h.date_entered }
            end
          end
          base
        end
      end
    end
  end
end
