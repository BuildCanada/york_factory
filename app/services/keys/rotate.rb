module Keys
  # Replaces a key with a new one with the same settings. The old key keeps
  # working for the grace period (none, 1 hour, 24 hours or 7 days), then
  # stops (docs/public-interface-design.md §4.3, "Rotate").
  class Rotate
    Result = Keys::Issue::Result

    class NotRotatable < StandardError; end

    def self.call(**) = new(**).call

    def initialize(api_key:, user:, context:, grace: ApiKey::DEFAULT_GRACE_PERIOD, issuer: KeyIssuers.default)
      @api_key = api_key
      @user = user
      @context = context
      @grace = ApiKey::GRACE_PERIODS.fetch(grace.to_s) { raise ArgumentError, "Unknown grace period #{grace.inspect}" }
      @grace_name = grace.to_s
      @issuer = issuer
    end

    def call
      raise NotRotatable, "Only an active key can be rotated" unless @api_key.usable?
      raise NotRotatable, "This key has already been rotated" if @api_key.rotated_to.present?

      now = Time.current
      result = nil
      ApiKey.transaction do
        @api_key.lock!
        grace_until = [ now + @grace, @api_key.grace_until ].compact.min
        # Set before the new key is inserted: names are unique only among
        # keys that aren't being rotated out.
        @api_key.update!(grace_until:)
        result = Keys::Issue.call(
          account: @api_key.account,
          user: @user,
          name: @api_key.name,
          scopes: @api_key.scopes,
          expires_in: lifetime,
          allowed_origins: @api_key.allowed_origins,
          allowed_ips: @api_key.allowed_ips,
          rotated_from: @api_key,
          issuer: @issuer,
          context: @context
        )
        raise ActiveRecord::Rollback unless result.ok?

        AuditEvent.record!("key.rotated", context: @context, account: @api_key.account, subject: @api_key,
          metadata: { new_key_id: result.api_key.id, grace: @grace_name, grace_until: grace_until.iso8601 })
      end

      if result.ok?
        @api_key.reload
        if @grace.zero?
          Keys::Revoke.call(api_key: @api_key, reason: "rotated", context: @context)
        else
          ActiveRecord.after_all_transactions_commit { Edge::Push.key(@api_key) }
        end
      else
        @api_key.reload
      end
      result
    end

    private

    # A rotated key lives as long as the original did, counted from now.
    def lifetime
      return nil if @api_key.expires_at.nil?

      [ (@api_key.expires_at - @api_key.created_at).seconds, 1.day ].max
    end
  end
end
