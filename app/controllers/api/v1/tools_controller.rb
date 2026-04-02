module Api
  module V1
    class ToolsController < CmsBaseController
      before_action :authenticate_admin!, only: [ :create, :update, :destroy, :bulk_update ]
      before_action :set_tool, only: [ :update, :destroy ]

      def index
        scope = preview_mode? ? Tool.all : Tool.published
        scope = scope.with_attached_image.ordered
        scope = scope.featured if params[:featured].present?

        render json: {
          data: scope.map { |t| serialize_tool(t) }
        }
      end

      def create
        tool = Tool.new(tool_params)
        if tool.save
          render json: serialize_tool(tool), status: :created
        else
          render json: { errors: tool.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @tool.update(tool_params)
          render json: serialize_tool(@tool)
        else
          render json: { errors: @tool.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def bulk_update
        ActiveRecord::Base.transaction do
          updates = params.require(:tools)
          updates.each do |entry|
            tool = Tool.find(entry[:id])
            tool.update!(entry.permit(:position, :featured, :slug, :title_en, :title_fr))
          end
        end
        render json: { message: "Updated" }
      end

      def destroy
        @tool.destroy!
        head :no_content
      end

      private

      def set_tool
        @tool = Tool.find(params[:id])
      end

      def tool_params
        params.require(:tool).permit(
          :url, :featured, :position, :accent_color, :size, :image,
          :title_en, :title_fr, :description_en, :description_fr
        )
      end

      def serialize_tool(tool)
        {
          id: tool.id,
          slug: tool.slug,
          title: tool.title,
          description: tool.description.to_s,
          url: tool.url,
          featured: tool.featured,
          position: tool.position,
          accent_color: tool.accent_color,
          size: tool.size,
          image_url: tool.image.attached? ? url_for(tool.image) : nil
        }
      end
    end
  end
end
