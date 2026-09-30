module Admin
  module Developers
    # Staff view of accounts, keys and the audit log
    # (docs/public-interface-design.md §4.5).
    class BaseController < Admin::BaseController
      private

      def audit_context = AuditEvent::Context.from_request(request, actor: current_user, actor_kind: "admin")

      def require_superadmin!
        redirect_to admin_developers_root_path, alert: "Only superadmins can do that." unless current_user.superadmin?
      end
    end
  end
end
