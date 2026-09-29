module Developers
  class KeysController < BaseController
    before_action :require_key_manager!, except: %i[index show live]
    before_action :set_key, only: %i[show edit update destroy rotate live]

    def index
      @api_keys = @account.api_keys.includes(:rotated_to).order(created_at: :desc)
      @key_hours = Usage::Report.key_hours(@account)
    end

    def new
      @api_key = @account.api_keys.new(scopes: ApiKey::DEFAULT_SCOPES)
      @expiry = ApiKey::DEFAULT_EXPIRY
    end

    def create
      @expiry = ApiKey::EXPIRY_OPTIONS.key?(key_params[:expiry]) ? key_params[:expiry] : ApiKey::DEFAULT_EXPIRY
      result = Keys::Issue.call(
        account: @account,
        user: current_user,
        name: key_params[:name],
        scopes: Array(key_params[:scopes]),
        expires_in: ApiKey::EXPIRY_OPTIONS.fetch(@expiry),
        allowed_origins: split_list(key_params[:allowed_origins]),
        allowed_ips: split_list(key_params[:allowed_ips]),
        context: audit_context
      )
      @api_key = result.api_key

      if result.ok?
        show_raw_key(result.raw_key)
        render :show, status: :created
      else
        render :new, status: result.api_key.errors[:base].include?(Keys::Issue::UNAVAILABLE_MESSAGE) ? :service_unavailable : :unprocessable_entity
      end
    end

    def show
      load_key_detail
    end

    # The key's live panel (last hour by minute, and the edge's bucket and
    # quota), fetched by the key page every 10 seconds.
    def live
      load_live_usage
      render partial: "developers/keys/live", locals: { api_key: @api_key, minutes: @minutes, edge: @edge_usage }
    end

    def edit
    end

    def update
      attributes = {
        name: key_params[:name],
        scopes: Array(key_params[:scopes]),
        allowed_origins: split_list(key_params[:allowed_origins]),
        allowed_ips: split_list(key_params[:allowed_ips])
      }
      if Keys::Update.call(api_key: @api_key, user: current_user, attributes:, context: audit_context)
        redirect_to developers_key_path(@api_key), notice: "Key updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Revoking asks for the key's name, typed, as confirmation.
    def destroy
      if params[:confirm_name].to_s.strip != @api_key.name
        redirect_to developers_key_path(@api_key), alert: "Type the key's name exactly to revoke it."
        return
      end

      Keys::Revoke.call(api_key: @api_key, reason: "user", context: audit_context)
      redirect_to developers_keys_path, notice: "Key \"#{@api_key.name}\" revoked. It stops working at once."
    end

    def rotate
      grace = ApiKey::GRACE_PERIODS.key?(params[:grace]) ? params[:grace] : ApiKey::DEFAULT_GRACE_PERIOD
      result = Keys::Rotate.call(api_key: @api_key, user: current_user, grace:, context: audit_context)

      if result.ok?
        @api_key = result.api_key
        show_raw_key(result.raw_key)
        render :show, status: :created
      else
        redirect_to developers_key_path(@api_key), alert: result.api_key.errors.full_messages.to_sentence
      end
    rescue Keys::Rotate::NotRotatable => error
      redirect_to developers_key_path(@api_key), alert: error.message
    end

    private

    def set_key
      @api_key = @account.api_keys.find(params[:id])
    end

    # The raw key is rendered once, in this response, and never stored in the
    # session or flash. no-store keeps it out of browser and proxy caches.
    def show_raw_key(raw_key)
      @raw_key = raw_key
      response.headers["Cache-Control"] = "no-store"
      load_key_detail
    end

    def load_key_detail
      key_ids = [ @api_key.id, @api_key.rotated_from_id ].compact
      @audit_events = AuditEvent.where(subject_type: "ApiKey", subject_id: key_ids).recent.includes(:actor_user).limit(100)
      @report = Usage::Report.new(account: @account, api_key: @api_key)
      @quota = Usage::Quota.new(@account)
      load_live_usage
    end

    def load_live_usage
      now = Time.current.utc.beginning_of_minute + 1.minute
      live = Usage::Live.new
      @live_configured = live.configured?
      @minutes = live.minutes(account: @account, api_key: @api_key, from: now - 60.minutes, to: now)
      @edge_usage = Edge::UsageClient.new.key(@api_key) if @api_key.usable?
    end

    def key_params
      params.fetch(:api_key, {}).permit(:name, :expiry, :allowed_origins, :allowed_ips, scopes: [])
    end

    def split_list(value) = value.to_s.split(/[\s,]+/).compact_blank
  end
end
