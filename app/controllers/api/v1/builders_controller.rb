module Api
  module V1
    class BuildersController < CmsBaseController
      before_action :authenticate_admin!, only: [ :create, :update, :destroy ]
      before_action :set_builder, only: [ :show, :update, :destroy ]

      def index
        scope = preview_mode? ? Builder.all : Builder.published
        pagy, builders = pagy(scope.with_attached_image.order(:created_at))
        render json: {
          data: builders.map { |b| serialize_builder(b) },
          pagination: pagy_metadata(pagy)
        }
      end

      def show
        render json: serialize_builder(@builder, full: true)
      end

      def create
        builder = Builder.new(builder_params)
        if builder.save
          render json: serialize_builder(builder, full: true), status: :created
        else
          render json: { errors: builder.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @builder.update(builder_params)
          render json: serialize_builder(@builder, full: true)
        else
          render json: { errors: @builder.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @builder.destroy!
        head :no_content
      end

      private

      def set_builder
        scope = preview_mode? ? Builder.all : Builder.published
        @builder = scope.friendly.find(params[:slug])
      end

      def builder_params
        params.require(:builder).permit(
          :image, :published_at,
          :title_en, :title_fr, :byline_en, :byline_fr,
          :quote_en, :quote_fr, :author_en, :author_fr,
          :body_en, :body_fr
        )
      end

      def serialize_builder(builder, full: false)
        data = {
          id: builder.id,
          slug: builder.slug,
          title: builder.title,
          byline: builder.byline,
          quote: builder.quote,
          image_url: builder.image.attached? ? url_for(builder.image) : nil
        }
        if full
          data[:body] = builder.body.to_s
          data[:author] = builder.author.to_s
        end
        data
      end
    end
  end
end
