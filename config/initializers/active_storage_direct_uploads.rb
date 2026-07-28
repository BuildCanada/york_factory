# Rails draws POST /rails/active_storage/direct_uploads with no
# authentication, letting anyone create blob records and obtain presigned R2
# PUT URLs. Nothing in the app uses direct uploads (the admin markdown editor
# proxies through /admin/uploads), so require an admin session — the same rule
# as Admin::BaseController — rather than leaving the endpoint open.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.class_eval do
    before_action :require_admin_for_direct_uploads

    private

    def require_admin_for_direct_uploads
      user = request.env["warden"]&.user(:user)
      head :unauthorized unless user&.admin?
    end
  end
end
