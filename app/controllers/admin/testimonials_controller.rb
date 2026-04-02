module Admin
  class TestimonialsController < BaseController
    before_action :set_testimonial, only: [ :show, :edit, :update, :destroy, :retranslate ]

    def index
      @testimonials = Testimonial.ordered
    end

    def show; end
    def new; @testimonial = Testimonial.new; end
    def edit; end

    def create
      @testimonial = Testimonial.new(testimonial_params)
      if @testimonial.save
        redirect_to admin_testimonial_path(@testimonial), notice: "Testimonial created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      purge_attachment(:profile_photo)
      purge_attachment(:splash_photo)
      if @testimonial.update(testimonial_params)
        redirect_to admin_testimonial_path(@testimonial), notice: "Testimonial updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @testimonial.destroy!
      redirect_to admin_testimonials_path, notice: "Testimonial deleted."
    end

    def reorder
      params[:ordered_ids].each_with_index do |id, index|
        Testimonial.where(id: id).update_all(position: index)
      end
      head :ok
    end

    def retranslate
      @testimonial.update(quote_fr: nil)
      TranslateRecordJob.perform_later(@testimonial)
      head :ok
    end

    private

    def set_testimonial
      @testimonial = Testimonial.find(params[:id])
    end

    def testimonial_params
      params.require(:testimonial).permit(
        :name, :position, :published_at, :profile_photo, :splash_photo,
        :quote_en, :quote_fr
      )
    end

    def purge_attachment(name)
      @testimonial.send(name).purge if params.dig(:testimonial, "purge_#{name}") == "1"
    end
  end
end
