module Developers
  # Accepting the data terms unlocks read:persons (docs/public-interface-design.md §4.2).
  class TermsController < BaseController
    before_action :require_key_manager!

    def create
      unless @account.terms_accepted?
        @account.transaction do
          @account.update!(terms_accepted_at: Time.current)
          AuditEvent.record!("account.terms_accepted", context: audit_context, account: @account, subject: @account)
        end
      end
      redirect_to developers_path, notice: "Data terms accepted. New keys can now include read:persons."
    end
  end
end
