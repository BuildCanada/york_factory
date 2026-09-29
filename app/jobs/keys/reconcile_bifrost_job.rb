module Keys
  # Nightly check that Bifrost and york_factory agree about data API keys
  # (docs/public-interface-design.md §4.3):
  #
  # - deactivates data-api:* virtual keys that are active in Bifrost but have
  #   no usable key here (orphans from a failed issue, revoked or expired
  #   keys, keys past their rotation grace);
  # - reports the reverse, usable Bifrost-issued keys whose virtual key is
  #   missing or inactive in Bifrost, without changing them.
  #
  # The report is an admin.bifrost_reconciled audit event, shown on
  # /admin/developers.
  class ReconcileBifrostJob < ApplicationJob
    queue_as :default

    # Keys that should keep an active virtual key. A suspended account's keys
    # do, so lifting the suspension needs no Bifrost change.
    KEEP_STATUSES = %w[active rotating suspended].freeze

    def perform(client: nil)
      unless client || BifrostClient.configured?
        Rails.logger.info("[Keys::ReconcileBifrostJob] Bifrost is not configured; skipping")
        return
      end
      client ||= BifrostClient.new

      virtual_keys = client.list_virtual_keys.select { |vk| KeyIssuers::BifrostIssuer.parse_virtual_key_name(vk.name) }
      keys_by_vk_id = ApiKey.bifrost.where(bifrost_vk_id: virtual_keys.map(&:id)).index_by(&:bifrost_vk_id)

      deactivated = []
      failed = []
      virtual_keys.each do |vk|
        next unless vk.is_active
        next if keys_by_vk_id[vk.id]&.status.in?(KEEP_STATUSES)

        begin
          client.deactivate_virtual_key(vk.id)
          deactivated << { vk_id: vk.id, name: vk.name, key_id: keys_by_vk_id[vk.id]&.id }
        rescue BifrostClient::Error => error
          failed << { vk_id: vk.id, name: vk.name, error: error.class.name }
        end
      end

      active_vk_ids = virtual_keys.select(&:is_active).map(&:id).to_set
      missing = ApiKey.bifrost.live.includes(:account).select(&:usable?).reject { |key| active_vk_ids.include?(key.bifrost_vk_id) }
        .map { |key| { key_id: key.id, account_id: key.account_id, prefix: key.token_prefix, vk_id: key.bifrost_vk_id } }

      AuditEvent.record!("admin.bifrost_reconciled", context: AuditEvent::Context.system, metadata: {
        checked: virtual_keys.size, deactivated:, failed:, missing_in_bifrost: missing
      })
    end
  end
end
