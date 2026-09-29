module Keys
  # Renames, rescopes or restricts a live key. Widening its scopes is audited
  # separately and emailed to the owner (docs/public-interface-design.md §4.4).
  class Update
    ATTRIBUTES = %i[name scopes allowed_origins allowed_ips].freeze

    def self.call(**) = new(**).call

    def initialize(api_key:, user:, attributes:, context:)
      @api_key = api_key
      @user = user
      @attributes = attributes.to_h.symbolize_keys.slice(*ATTRIBUTES)
      @context = context
    end

    # Returns true on success; errors are on the key otherwise.
    def call
      unless @api_key.usable?
        @api_key.errors.add(:base, "Only an active key can be changed")
        return false
      end

      previous_scopes = @api_key.scopes
      @api_key.assign_attributes(@attributes)
      @api_key.validate
      Keys::Policy.new(@api_key.account, @user).check_update(@api_key)
      return false if @api_key.errors.any?

      changes = @api_key.changes_to_save.except("updated_at").transform_values { |(from, to)| { from:, to: } }
      return true if changes.empty?

      widened = @api_key.scopes - previous_scopes
      ApiKey.transaction do
        @api_key.save!
        AuditEvent.record!("key.updated", context: @context, account: @api_key.account, subject: @api_key, metadata: { changes: })
        if widened.any?
          AuditEvent.record!("key.scopes_widened", context: @context, account: @api_key.account, subject: @api_key, metadata: { added: widened })
        end
      end

      ActiveRecord.after_all_transactions_commit do
        Edge::Push.key(@api_key)
        DevelopersMailer.with(api_key: @api_key, event: "scopes_widened").key_changed.deliver_later if widened.any?
      end
      true
    end
  end
end
