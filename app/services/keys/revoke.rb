module Keys
  # Revokes a key (docs/public-interface-design.md §4.3, "Revoke"): sets
  # revoked_at, pushes the revocation to the edge, then deactivates the
  # Bifrost virtual key. Rails is the source of truth, so the revoke succeeds
  # even if Bifrost is down; the deactivation is retried in the background
  # and caught by the nightly reconciliation.
  class Revoke
    REASONS = %w[user rotated admin leak mass_rotation account_suspended].freeze

    def self.call(**) = new(**).call

    def initialize(api_key:, reason:, context:)
      @api_key = api_key
      @reason = reason.to_s
      raise ArgumentError, "Unknown revoke reason #{reason.inspect}" unless REASONS.include?(@reason)

      @context = context
    end

    def call
      return false if @api_key.revoked_at?

      ApiKey.transaction do
        @api_key.update!(revoked_at: Time.current, revoked_reason: @reason)
        AuditEvent.record!(@reason == "leak" ? "key.revoked.leak" : "key.revoked",
          context: @context, account: @api_key.account, subject: @api_key,
          metadata: { name: @api_key.name, reason: @reason })
      end

      ActiveRecord.after_all_transactions_commit do
        Edge::Push.key(@api_key)
        deactivate_in_bifrost if @api_key.bifrost?
        DevelopersMailer.with(api_key: @api_key, event: "revoked").key_changed.deliver_later if notify?
      end
      true
    end

    private

    def deactivate_in_bifrost
      @api_key.deactivate_in_bifrost!
    rescue KeyIssuers::Unavailable => error
      Rails.logger.warn("[Keys::Revoke] key #{@api_key.id}: Bifrost deactivation deferred (#{error.message})")
      @api_key.deactivate_in_bifrost_later!
    end

    # A zero-grace rotation already sends the rotation email.
    def notify? = @reason != "rotated" && (@context.actor_kind != "system" || @reason == "leak")
  end
end
