module Admin
  class BuildersController < BaseController
    before_action :set_builder, only: [ :show, :edit, :update, :destroy, :retranslate ]

    def index
      @pagy, @builders = pagy(Builder.order(created_at: :desc))
    end

    def show; end
    def new; @builder = Builder.new; end
    def edit; end

    def create
      @builder = Builder.new(builder_params)
      if @builder.save
        redirect_to admin_builder_path(@builder), notice: "Builder created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      purge_attachment(:image)
      if @builder.update(builder_params)
        redirect_to admin_builder_path(@builder), notice: "Builder updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @builder.destroy!
      redirect_to admin_builders_path, notice: "Builder deleted."
    end

    def retranslate
      @builder.update(title_fr: nil, byline_fr: nil, quote_fr: nil)
      @builder.body_fr = nil
      @builder.author_fr = nil
      @builder.save!
      TranslateRecordJob.perform_later("Builder", @builder.id)
      head :ok
    end

    private

    def set_builder
      @builder = Builder.friendly.find(params[:id])
    end

    def builder_params
      params.require(:builder).permit(
        :published_at, :image,
        :title_en, :title_fr, :byline_en, :byline_fr,
        :quote_en, :quote_fr,
        :body_en, :body_fr, :author_en, :author_fr
      )
    end

    def purge_attachment(name)
      @builder.send(name).purge if params.dig(:builder, "purge_#{name}") == "1"
    end
  end
end
