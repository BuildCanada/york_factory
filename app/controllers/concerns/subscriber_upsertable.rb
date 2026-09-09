# Shared "upsert a Subscriber from a public form submission" behaviour.
#
# Several public endpoints (vote pledges, resident surveys) take an email plus
# some contact details and need the same thing: reuse the subscriber row for
# that email if we already have one, otherwise build it, and let the form fill
# in blanks without ever overwriting what a subscriber already told us.
#
# Extracted from Api::V1::ElectionPledgesController when the survey endpoint
# became the second caller.
module SubscriberUpsertable
  extend ActiveSupport::Concern

  private

  # Reuses an existing subscriber row for the email (case-insensitive) or
  # builds one. A name or postal code on the form fills in blank subscriber
  # fields but never overwrites what a subscriber already told us.
  #
  # `source` labels where the signup came from and is only set when the
  # subscriber doesn't already carry one — the first form someone submits is
  # how we found them.
  def find_or_build_subscriber(source:)
    email = params[:email].to_s.strip
    subscriber = Subscriber.where("LOWER(email) = ?", email.downcase).first ||
      Subscriber.new(email: email)

    first, last = submitted_name_parts
    subscriber.first_name = first if subscriber.first_name.blank? && first.present?
    subscriber.last_name = last if subscriber.last_name.blank? && last.present?

    postal_code = params[:postal_code].to_s.strip.upcase
    subscriber.postal_code = postal_code if subscriber.postal_code.blank? && postal_code.present?

    subscriber.source ||= source
    %i[placement page_uri page_name hubspot_utk ip_address].each do |attr|
      subscriber[attr] = params[attr] if subscriber[attr].blank? && params[attr].present?
    end
    subscriber
  end

  # The name on this submission as [first, last].
  #
  # Two shapes reach here. Forms that ask for the two parts separately (the
  # resident survey, since HubSpot's newsletter form requires both firstname
  # and lastname and a whitespace split can't be trusted to supply them) send
  # `first_name` and `last_name`. Forms that ask for one line — the vote
  # pledge, and any tracker build older than the split — send `name`, which is
  # split on whitespace as before.
  #
  # Explicit parts win where both arrive, and each falls back on its own: a
  # client that sends only `first_name` still gets a last name out of `name`
  # if it sent one.
  def submitted_name_parts
    split_first, split_last = split_name(params[:name])

    [
      params[:first_name].to_s.strip.presence || split_first,
      params[:last_name].to_s.strip.presence || split_last
    ]
  end

  def split_name(raw)
    parts = raw.to_s.strip.split(/\s+/)
    return [ nil, nil ] if parts.empty?

    [ parts[0..-2].presence&.join(" ") || parts.first, parts.length > 1 ? parts.last : nil ]
  end

  def display_name(subscriber)
    [ subscriber.first_name, subscriber.last_name ].compact_blank.join(" ").presence
  end
end
