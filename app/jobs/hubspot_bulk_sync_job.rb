class HubspotBulkSyncJob < ApplicationJob
  queue_as :default

  def perform(sync_type, **options)
    case sync_type.to_sym
    when :all
      sync_all_contacts
    when :stale
      sync_stale_contacts
    when :recent
      sync_recent_contacts(options[:hours] || 24)
    else
      Rails.logger.error "Unknown sync type: #{sync_type}"
    end
  end

  private

  def sync_all_contacts
    Rails.logger.info "Starting bulk sync of all Hubspot contacts"
    sync_service = HubspotSyncService.new
    sync_service.sync_all_contacts_from_hubspot
  end

  def sync_stale_contacts
    Rails.logger.info "Starting sync of stale Hubspot contacts"
    sync_service = HubspotSyncService.new
    sync_service.sync_stale_contacts_from_hubspot
  end

  def sync_recent_contacts(hours)
    Rails.logger.info "Starting sync of recently updated Hubspot contacts (#{hours} hours)"
    sync_service = HubspotSyncService.new
    sync_service.sync_recently_updated_contacts_from_hubspot(hours: hours)
  end
end
