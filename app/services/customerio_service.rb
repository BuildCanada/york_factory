# Identifies subscribers to Customer.io through the CDP identify endpoint.
#
# Runs alongside the HubSpot sync rather than replacing it: identify is an
# upsert of a person's traits, so unlike the HubSpot form path it carries no
# "this person just subscribed" meaning and is safe to send on every change.
#
# The CDP write key authenticates as HTTP Basic with the key as the username
# and an empty password, i.e. `Authorization: Basic base64("#{key}:")`.
class CustomerioService
  IDENTIFY_URL = "https://cdp.customer.io/v1/identify".freeze
  EU_IDENTIFY_URL = "https://cdp-eu.customer.io/v1/identify".freeze

  class ConfigurationError < StandardError; end
  class IdentifyError < StandardError; end

  def self.identify_subscriber(subscriber)
    new.identify_subscriber(subscriber)
  end

  def initialize(api_key: default_api_key, url: default_url)
    @api_key = api_key
    @url = url
  end

  def identify_subscriber(subscriber)
    if skip_identify?
      Rails.logger.info "Skipping Customer.io identify for #{subscriber.email} " \
        "(development without ENABLE_CUSTOMERIO_IDENTIFY)"
      return false
    end

    raise ConfigurationError, "Set customerio.api_key in Rails credentials to identify subscribers" if @api_key.blank?

    # The subscriber's row id keys the person, so a later email change updates
    # the same Customer.io profile instead of creating a second one.
    user_id = subscriber.id
    raise IdentifyError, "Cannot identify an unsaved subscriber (#{subscriber.email})" if user_id.blank?

    # `newsletter_opt_in` is merged in after compact_blank rather than sitting
    # in the hash: false is blank, so compacting would drop the very value an
    # opt-out needs to send and leave Customer.io subscribed.
    traits = {
      email: subscriber.email,
      first_name: subscriber.first_name,
      last_name: subscriber.last_name,
      name: [ subscriber.first_name, subscriber.last_name ].compact_blank.join(" ").presence,
      postal_code: subscriber.postal_code,
      city: subscriber.city,
      province: subscriber.province,
      source: subscriber.source,
      placement: subscriber.placement,
      pledged_to_vote_at: subscriber.pledged_to_vote_at,
      created_at: subscriber.created_at
    }.compact_blank.merge(newsletter_opt_in: subscriber.newsletter_opt_in)

    response = HTTP.post(@url,
      json: { userId: user_id.to_s, traits: traits },
      headers: { "Authorization" => "Basic #{basic_credentials}" })

    unless response.status.success?
      raise IdentifyError,
        "Customer.io identify failed for #{subscriber.email}: #{response.status} #{response.body.to_s.truncate(300)}"
    end

    Rails.logger.info "Identified subscriber #{subscriber.email} to Customer.io"
    true
  end

  private

  # Local development must not write to the production Customer.io workspace
  # by default; opt in with ENABLE_CUSTOMERIO_IDENTIFY=1.
  def skip_identify?
    Rails.env.development? && ENV["ENABLE_CUSTOMERIO_IDENTIFY"].blank?
  end

  def basic_credentials
    Base64.strict_encode64("#{@api_key}:")
  end

  def default_api_key
    Rails.application.credentials.dig(:customerio, :api_key)
  end

  # US workspaces post to cdp.customer.io, EU ones to cdp-eu.customer.io; set
  # customerio.region to "eu" for the latter.
  def default_url
    Rails.application.credentials.dig(:customerio, :region).to_s.downcase == "eu" ? EU_IDENTIFY_URL : IDENTIFY_URL
  end
end
