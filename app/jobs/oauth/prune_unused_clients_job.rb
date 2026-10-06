module Oauth
  # Deletes public-API OAuth clients that were registered (dynamically, or
  # from a Client ID Metadata Document) more than a week ago and never
  # authorized, so open registration can't fill the table
  # (docs/public-interface-design.md §8.2). A metadata-document client comes
  # back on its next authorization request. Runs nightly.
  class PruneUnusedClientsJob < ApplicationJob
    queue_as :default

    AFTER = 7.days
    BATCH = 500

    def perform(now: Time.current)
      pruned = 0
      loop do
        ids = Doorkeeper::Application.where(client_type: %w[dynamic metadata_document], trusted: false, reviewed_at: nil)
          .where(created_at: ...(now - AFTER))
          .where.not(id: Doorkeeper::AccessGrant.select(:application_id))
          .where.not(id: Doorkeeper::AccessToken.select(:application_id))
          .limit(BATCH).pluck(:id)
        break if ids.empty?

        pruned += Doorkeeper::Application.where(id: ids).delete_all
      end
      return if pruned.zero?

      AuditEvent.record!("admin.oauth_clients_pruned", context: AuditEvent::Context.system, metadata: { pruned:, older_than_days: AFTER.in_days.to_i })
    end
  end
end
