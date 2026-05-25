module Api
  module V1
    module Kpis
      module Admin
        class DocumentsController < BaseController
          def create
            attrs = document_params

            jurisdiction = ::Warehouse::Jurisdiction.find_by!(slug: attrs.delete(:jurisdiction_slug))
            organization = if (slug = attrs.delete(:organization_slug))
              jurisdiction.organizations.find_by!(slug: slug)
            end

            doc = ::Warehouse::KpiDocument.find_or_initialize_by(doc_url: attrs.fetch(:doc_url))
            doc.assign_attributes(
              jurisdiction_id: jurisdiction.id,
              organization_id: organization&.id,
              fiscal_year: attrs.fetch(:fiscal_year),
              published_at: attrs[:published_at],
              published_at_source: attrs[:published_at_source] || "manual",
              source_page_url: attrs[:source_page_url],
              doc_title: attrs[:doc_title],
              doc_type: attrs[:doc_type],
              filepath: attrs[:filepath],
              content_hash: attrs[:content_hash]
            )
            doc.save!

            render json: serialize(doc), status: :ok
          end

          private

          def document_params
            params.require(:document).permit(
              :jurisdiction_slug, :organization_slug, :fiscal_year, :published_at,
              :published_at_source, :source_page_url, :doc_url, :doc_title,
              :doc_type, :filepath, :content_hash
            ).to_h.symbolize_keys
          end

          def serialize(doc)
            {
              id: doc.id,
              doc_url: doc.doc_url,
              fiscal_year: doc.fiscal_year,
              jurisdiction_id: doc.jurisdiction_id,
              organization_id: doc.organization_id,
              published_at: doc.published_at,
              published_at_source: doc.published_at_source
            }
          end
        end
      end
    end
  end
end
