module Admin
  # Receives inline file uploads from the markdown editor (paste, drag & drop,
  # upload button) and stores them as ActiveStorage blobs. Uploads are proxied
  # through the app rather than sent to the storage service from the browser,
  # so no cross-origin (R2 CORS) configuration is required. Returns an absolute
  # blob URL because CMS markdown is rendered on other hosts (buildcanada.com).
  class UploadsController < BaseController
    def create
      file = params.require(:file)

      blob = ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: file.original_filename,
        content_type: file.content_type
      )

      render json: {
        signed_id: blob.signed_id,
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        url: rails_blob_url(blob)
      }, status: :created
    rescue ActionController::ParameterMissing
      render json: { error: "file is required" }, status: :unprocessable_entity
    end
  end
end
