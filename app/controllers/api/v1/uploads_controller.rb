module Api
  module V1
    class UploadsController < CmsBaseController
      before_action :authenticate_admin!

      def create
        blob = ActiveStorage::Blob.create_and_upload!(
          io: params[:file],
          filename: params[:file].original_filename,
          content_type: params[:file].content_type
        )

        render json: {
          signed_id: blob.signed_id,
          url: url_for(blob)
        }, status: :created
      end
    end
  end
end
