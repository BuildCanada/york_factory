module Admin
  module Developers
    class KeysController < BaseController
      STATUSES = %w[live revoked].freeze

      def index
        scope = ApiKey.includes(:account, :user).order(created_at: :desc)
        scope = scope.where("api_keys.token_prefix LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(params[:prefix].strip)}%") if params[:prefix].present?
        scope = scope.live if params[:status] == "live"
        scope = scope.where.not(revoked_at: nil) if params[:status] == "revoked"
        scope = scope.where(issuer: params[:issuer]) if params[:issuer].in?(ApiKey::ISSUERS)
        @pagy, @api_keys = pagy(scope)
      end

      def revoke
        api_key = ApiKey.find(params[:id])
        reason = params[:reason].in?(%w[admin leak]) ? params[:reason] : "admin"
        Keys::Revoke.call(api_key:, reason:, context: audit_context)
        redirect_back fallback_location: admin_developers_keys_path, notice: "Key #{api_key.token_prefix}… revoked."
      end
    end
  end
end
