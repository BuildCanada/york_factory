module Api
  module V1
    class TestimonialsController < CmsBaseController
      before_action :authenticate_admin!, only: [:create, :destroy, :bulk_update]

      def index
        scope = preview_mode? ? Testimonial.all : Testimonial.published
        render json: {
          data: scope.ordered.map { |t| serialize_testimonial(t) }
        }
      end

      def create
        testimonial = Testimonial.new(testimonial_params)
        if testimonial.save
          render json: serialize_testimonial(testimonial), status: :created
        else
          render json: { errors: testimonial.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def bulk_update
        ActiveRecord::Base.transaction do
          updates = params.require(:testimonials)
          updates.each do |entry|
            t = Testimonial.find(entry[:id])
            t.update!(entry.permit(:position, :name, :quote_en, :quote_fr))
          end
        end
        render json: { message: "Updated" }
      end

      def destroy
        testimonial = Testimonial.find(params[:id])
        testimonial.destroy!
        head :no_content
      end

      private

      def testimonial_params
        params.require(:testimonial).permit(
          :name, :position, :profile_photo, :splash_photo,
          :quote_en, :quote_fr
        )
      end

      def serialize_testimonial(testimonial)
        {
          id: testimonial.id,
          name: testimonial.name,
          quote: testimonial.quote,
          position: testimonial.position,
          profile_photo_url: testimonial.profile_photo.attached? ? url_for(testimonial.profile_photo) : nil,
          splash_photo_url: testimonial.splash_photo.attached? ? url_for(testimonial.splash_photo) : nil
        }
      end

    end
  end
end
