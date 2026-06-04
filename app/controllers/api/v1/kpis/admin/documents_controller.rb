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
              content_hash: attrs[:content_hash],
              agent_run_id: attrs[:agent_run_id]
            )
            doc.save!

            render json: serialize(doc), status: :ok
          end

          # POST /api/v1/kpis/admin/documents/:id/archive
          # Body: the raw fetched document bytes (HTML or PDF), sent as-is.
          # Stores a snapshot in R2 and records its sha256 so reviewers can
          # verify they are looking at the same bytes the extractor saw.
          def archive
            doc = ::Warehouse::KpiDocument.find(params[:id])
            body = request.raw_post
            return render json: { error: "empty_body" }, status: :unprocessable_entity if body.blank?

            content_hash = Digest::SHA256.hexdigest(body)
            key = archive_key(doc, content_hash)

            begin
              R2Storage.new.upload(key: key, body: body)
            rescue => e
              # Record the hash even when storage is unavailable (e.g. dev
              # without R2 credentials) so same-document verification still works.
              doc.update!(content_hash: content_hash)
              return render json: {
                id: doc.id, content_hash: content_hash, archived: false,
                error: "archive_storage_failed", details: e.message
              }, status: :ok
            end

            doc.update!(content_hash: content_hash, filepath: key)
            render json: { id: doc.id, content_hash: content_hash, filepath: key, archived: true }, status: :ok
          end

          # GET /api/v1/kpis/admin/documents/:id/archive
          # Returns the archived snapshot bytes.
          def archive_download
            doc = ::Warehouse::KpiDocument.find(params[:id])
            return render json: { error: "not_archived" }, status: :not_found if doc.filepath.blank?

            body = R2Storage.new.download(key: doc.filepath)
            send_data body,
              type: doc.filepath.end_with?(".pdf") ? "application/pdf" : "text/html",
              disposition: "inline"
          rescue Aws::S3::Errors::NoSuchKey
            render json: { error: "archive_missing", filepath: doc.filepath }, status: :not_found
          end

          private

          def archive_key(doc, content_hash)
            ext = doc.doc_url.to_s.split("?").first.to_s.end_with?(".pdf") ? "pdf" : "html"
            "kpi_documents/#{doc.id}/#{content_hash}.#{ext}"
          end

          def document_params
            params.require(:document).permit(
              :jurisdiction_slug, :organization_slug, :fiscal_year, :published_at,
              :published_at_source, :source_page_url, :doc_url, :doc_title,
              :doc_type, :filepath, :content_hash, :agent_run_id
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
