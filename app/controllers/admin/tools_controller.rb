module Admin
  class ToolsController < BaseController
    before_action :set_tool, only: [ :show, :edit, :update, :destroy, :retranslate ]

    def index
      @tools = Tool.ordered
    end

    def show; end
    def new; @tool = Tool.new; end
    def edit; end

    def create
      @tool = Tool.new(tool_params)
      if @tool.save
        redirect_to admin_tool_path(@tool), notice: "Tool created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      purge_attachment(:image)
      if @tool.update(tool_params)
        redirect_to admin_tool_path(@tool), notice: "Tool updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @tool.destroy!
      redirect_to admin_tools_path, notice: "Tool deleted."
    end

    def reorder
      params[:ordered_ids].each_with_index do |id, index|
        Tool.where(id: id).update_all(position: index)
      end
      head :ok
    end

    def retranslate
      @tool.update(title_fr: nil)
      @tool.description_fr = nil
      @tool.save!
      TranslateRecordJob.perform_later("Tool", @tool.id)
      head :ok
    end

    private

    def set_tool
      @tool = Tool.friendly.find(params[:id])
    end

    def tool_params
      params.require(:tool).permit(
        :url, :featured, :position, :accent_color, :size, :published_at, :image,
        :title_en, :title_fr, :description_en, :description_fr
      )
    end

    def purge_attachment(name)
      @tool.send(name).purge if params.dig(:tool, "purge_#{name}") == "1"
    end
  end
end
