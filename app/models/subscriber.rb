class Subscriber < ApplicationRecord
  performs :submit_to_hubspot_form
  performs :sync_to_hubspot

  # Contact fields whose changes trigger a HubSpot form submission. Context
  # columns (source, placement, page_uri, ...) ride along but don't retrigger.
  HUBSPOT_SYNCED_FIELDS = %w[email first_name last_name postal_code].freeze

  # Vote pledges from the election tracker (rows cascade with the subscriber
  # in the DB).
  has_many :pledges_to_vote, class_name: "Warehouse::PledgeToVote"

  # Set while the pledge endpoint records a pledge for this subscriber: the
  # pledge stamp submits the HubSpot pledge form (which carries the same
  # contact fields), so the save that creates or fills in the contact must
  # not also submit the subscriber form.
  attr_accessor :pledging

  validates :email, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }

  # Solid Queue runs on a separate database, so the job must not be enqueued
  # until the subscriber row is committed and visible to the worker.
  after_commit :submit_to_hubspot_form_later, on: [ :create, :update ],
    if: -> { hubspot_fields_saved? && !pledging }

  # A vote pledge stamps pledged_to_vote_at (see Warehouse::PledgeToVote).
  # Every pledge submits the dedicated HubSpot pledge form so pledge
  # workflows fire; the timestamp itself goes through the direct CRM sync —
  # the pledge form (a clone of the subscriber form) has no such field.
  after_commit :sync_pledge_to_hubspot, on: [ :create, :update ],
    if: -> { saved_change_to_pledged_to_vote_at? }

  # Enqueue a direct CRM sync for every subscriber, spread out to stay under
  # HubSpot's search API rate limit. Used by `rake hubspot:backfill_subscribers`.
  def self.backfill_hubspot_sync(per_minute: 60)
    find_each.with_index do |subscriber, index|
      SyncToHubspotJob.set(wait: (index / per_minute.to_f).minutes).perform_later(subscriber)
    end
  end

  # New signups go through the HubSpot form so submission-triggered workflows
  # fire in HubSpot; pledges go through the dedicated pledge form.
  def submit_to_hubspot_form(form = :subscriber)
    HubspotFormsService.submit_subscriber(self, form: form)
  end

  # Direct CRM upsert, bypassing form workflows. Used for backfills and for
  # fields the subscriber form doesn't define (pledged_to_vote_at).
  def sync_to_hubspot
    HubspotContact.upsert_hubspot_user(
      email: email,
      properties: {
        firstname: first_name,
        lastname: last_name,
        postal_code: postal_code,
        newsletter_subscription: true,
        pledged_to_vote_at: pledged_to_vote_at
      }.compact_blank
    )
  end

  private

  def sync_pledge_to_hubspot
    submit_to_hubspot_form_later(:pledge)
    sync_to_hubspot_later
  end

  def hubspot_fields_saved?
    saved_changes.keys.intersect?(HUBSPOT_SYNCED_FIELDS)
  end
end
