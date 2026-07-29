# Submits contacts through the HubSpot Forms API rather than the CRM contacts
# API, so that form-submission workflows configured in HubSpot fire. The
# submission endpoint is public (keyed by portal ID + form GUID) and needs no
# access token.
class HubspotFormsService
  SUBMIT_URL = "https://api.hsforms.com/submissions/v3/integration/submit"
  CONTACT_OBJECT_TYPE_ID = "0-1"

  class ConfigurationError < StandardError; end
  class SubmissionError < StandardError; end

  def self.submit_subscriber(subscriber, form: :subscriber)
    new(form: form).submit_subscriber(subscriber)
  end

  def initialize(portal_id: default_portal_id, form: :subscriber, form_guid: nil)
    @portal_id = portal_id
    @form = form
    @form_guid = form_guid || default_form_guid
  end

  def submit_subscriber(subscriber)
    if skip_submission?
      Rails.logger.info "Skipping HubSpot form submission for #{subscriber.email} " \
        "(development without ENABLE_HUBSPOT_SUBMISSIONS)"
      return false
    end

    if @portal_id.blank? || @form_guid.blank?
      raise ConfigurationError,
        "Set hubspot.portal_id and hubspot.#{@form}_form_guid in Rails credentials to submit subscriber forms"
    end

    fields = {
      "email" => subscriber.email,
      "firstname" => subscriber.first_name,
      "lastname" => subscriber.last_name,
      "zip" => subscriber.postal_code,
      "member_source" => subscriber.source
    }.compact_blank.map { |name, value| { objectTypeId: CONTACT_OBJECT_TYPE_ID, name: name, value: value } }

    # HubSpot attributes the submission to a page and visitor when given the
    # tracking context captured at signup.
    context = {
      hutk: subscriber.hubspot_utk,
      pageUri: subscriber.page_uri,
      pageName: subscriber.page_name,
      ipAddress: subscriber.ip_address
    }.compact_blank

    payload = { fields: fields }
    payload[:context] = context if context.any?

    response = HTTP.post("#{SUBMIT_URL}/#{@portal_id}/#{@form_guid}", json: payload)

    unless response.status.success?
      raise SubmissionError,
        "HubSpot form submission failed for #{subscriber.email}: #{response.status} #{response.body.to_s.truncate(300)}"
    end

    Rails.logger.info "Submitted HubSpot form for subscriber #{subscriber.email}"
    true
  end

  private

  # Local development must not write to the production HubSpot portal by
  # default; opt in with ENABLE_HUBSPOT_SUBMISSIONS=1.
  def skip_submission?
    Rails.env.development? && ENV["ENABLE_HUBSPOT_SUBMISSIONS"].blank?
  end

  def default_portal_id
    Rails.application.credentials.dig(:hubspot, :portal_id)
  end

  # Each form has its own GUID credential: hubspot.subscriber_form_guid for
  # newsletter signups, hubspot.pledge_form_guid for vote pledges.
  def default_form_guid
    Rails.application.credentials.dig(:hubspot, :"#{@form}_form_guid")
  end
end
