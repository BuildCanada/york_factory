module Keys
  # The response to a Bifrost breach (docs/public-interface-design.md §8.3):
  # Bifrost's admin API returns virtual key values in plaintext, so every
  # Bifrost-issued key must be replaced.
  #
  # Every live key from the issuer is put on a 7-day grace period, which
  # makes it "rotating" in the console, and its owner is emailed to rotate
  # it. The owner's one-click rotation issues the replacement and shows it
  # once. The replacement isn't issued here, because a key nobody has seen
  # can only be delivered by storing or emailing it, and both are worse than
  # the risk they would close. After the grace period the old keys stop and
  # the nightly reconciliation deactivates them in Bifrost.
  class MassRotateJob < ApplicationJob
    queue_as :default

    GRACE = 7.days

    def perform(reason:, issuer: "bifrost", actor_id: nil)
      actor = actor_id && User.find_by(id: actor_id)
      context = AuditEvent::Context.new(actor:, actor_kind: actor ? "admin" : "system", ip: nil, user_agent: nil)
      grace_until = GRACE.from_now
      count = 0

      ApiKey.live.where(issuer:).includes(:account, :user).find_each do |api_key|
        next if api_key.grace_until && api_key.grace_until <= grace_until

        ApiKey.transaction do
          api_key.update!(grace_until:)
          AuditEvent.record!("key.mass_rotation", context:, account: api_key.account, subject: api_key,
            metadata: { reason:, grace_until: grace_until.iso8601 })
        end
        Edge::Push.key(api_key)
        DevelopersMailer.with(api_key:, event: "rotation_required").key_changed.deliver_later
        count += 1
      end

      AuditEvent.record!("admin.mass_rotation", context:, metadata: { reason:, issuer:, keys: count, grace_until: grace_until.iso8601 })
      count
    end
  end
end
