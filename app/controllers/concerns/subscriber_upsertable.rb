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

    first, last = split_name(params[:name])
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

  def split_name(raw)
    parts = raw.to_s.strip.split(/\s+/)
    return [ nil, nil ] if parts.empty?

    [ parts[0..-2].presence&.join(" ") || parts.first, parts.length > 1 ? parts.last : nil ]
  end

  def display_name(subscriber)
    [ subscriber.first_name, subscriber.last_name ].compact_blank.join(" ").presence
  end
end
