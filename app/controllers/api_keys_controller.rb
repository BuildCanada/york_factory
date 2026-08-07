class ApiKeysController < ProfileController
  def index
    load_api_keys
  end

  def create
    @api_key, @raw_api_key = ApiKey.issue!(user: current_user, name: api_key_params[:name])
    load_api_keys
    render :index, status: :created
  rescue ActiveRecord::RecordInvalid => error
    @api_key = error.record
    load_api_keys
    render :index, status: :unprocessable_entity
  end

  def destroy
    current_user.api_keys.active.find(params[:id]).revoke!
    redirect_to profile_api_keys_path, notice: "API key revoked."
  end

  private

  def load_api_keys
    @api_keys = current_user.api_keys.order(created_at: :desc)
    @api_key ||= current_user.api_keys.new
  end

  def api_key_params
    params.require(:api_key).permit(:name)
  end
end
