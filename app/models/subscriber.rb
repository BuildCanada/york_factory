class Subscriber < ApplicationRecord
  performs :submit_to_hubspot_form
  performs :sync_to_hubspot

  # Every column except timestamps feeds the HubSpot contact.
  HUBSPOT_SYNCED_FIELDS = %w[email first_name last_name postal_code].freeze

  # Vote pledges from the election tracker (rows cascade with the subscriber
  # in the DB).
  has_many :pledges_to_vote, class_name: "Warehouse::PledgeToVote"

  validates :email, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }

  # Solid Queue runs on a separate database, so the job must not be enqueued
  # until the subscriber row is committed and visible to the worker.
  after_commit :submit_to_hubspot_form_later, on: [ :create, :update ], if: :hubspot_fields_saved?

  # Enqueue a direct CRM sync for every subscriber, spread out to stay under
  # HubSpot's search API rate limit. Used by `rake hubspot:backfill_subscribers`.
  def self.backfill_hubspot_sync(per_minute: 60)
    find_each.with_index do |subscriber, index|
      SyncToHubspotJob.set(wait: (index / per_minute.to_f).minutes).perform_later(subscriber)
    end
  end

  # New signups go through the HubSpot form so submission-triggered workflows
  # fire in HubSpot.
  def submit_to_hubspot_form
    HubspotFormsService.submit_subscriber(self)
  end

  # Direct CRM upsert, bypassing form workflows. Only for backfills.
  def sync_to_hubspot
    HubspotContact.upsert_hubspot_user(
      email: email,
      properties: {
        firstname: first_name,
        lastname: last_name,
        postal_code: postal_code,
        newsletter_subscription: true
      }.compact_blank
    )
  end

  private

  def hubspot_fields_saved?
    saved_changes.keys.intersect?(HUBSPOT_SYNCED_FIELDS)
  end
end
