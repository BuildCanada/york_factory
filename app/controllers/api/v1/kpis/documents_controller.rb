module Api
  module V1
    module Kpis
      class DocumentsController < BaseController
        def index
          scope = ::Warehouse::KpiDocument.includes(:jurisdiction, :organization)

          if params[:jurisdiction_slug].present?
            jur = ::Warehouse::Jurisdiction.find_by!(slug: params[:jurisdiction_slug])
            scope = scope.where(jurisdiction_id: jur.id)
          end

          if params[:organization_slug].present?
            org = resolve_organization_by_slug!(
              params[:organization_slug],
              jurisdiction_slug: params[:jurisdiction_slug]
            )
            scope = scope.where(organization_id: org.id)
          end

          scope = scope.where(fiscal_year: params[:fiscal_year]) if params[:fiscal_year].present?

          if params[:published_after].present?
            scope = scope.where("published_at >= ?", Date.parse(params[:published_after]))
          end

          if params[:published_before].present?
            scope = scope.where("published_at <= ?", Date.parse(params[:published_before]))
          end

          if params[:q].present?
            scope = scope.where("doc_title ILIKE ? OR doc_url ILIKE ?", "%#{params[:q]}%", "%#{params[:q]}%")
          end

          scope = scope.order(published_at: :desc, fiscal_year: :desc, id: :desc)
          pagy, docs = pagy(scope, limit: (params[:per_page] || 50).to_i)

          render json: { data: docs.map { |d| serialize(d) }, meta: pagy_metadata(pagy) }
        end

        def show
          doc = ::Warehouse::KpiDocument.includes(:jurisdiction, :organization).find(params[:id])
          citation_count = ::Warehouse::ExtractedObservation.where(document_id: doc.id).count
          measure_count  = ::Warehouse::ExtractedObservation.where(document_id: doc.id).distinct.count(:measure_id)
          render json: serialize(doc).merge(citation_count: citation_count, measure_count: measure_count)
        end

        private

        def serialize(d)
          {
            id: d.id,
            doc_url: d.doc_url,
            doc_title: d.doc_title,
            doc_type: d.doc_type,
            fiscal_year: d.fiscal_year,
            published_at: d.published_at,
            published_at_source: d.published_at_source,
            content_hash: d.content_hash,
            archived: d.filepath.present?,
            jurisdiction: d.jurisdiction && { id: d.jurisdiction.id, slug: d.jurisdiction.slug, name: d.jurisdiction.name },
            organization: d.organization && { id: d.organization.id, slug: d.organization.slug, canonical_name: d.organization.canonical_name }
          }
        end
      end
    end
  end
end
