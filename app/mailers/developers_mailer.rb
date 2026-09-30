# Tells an account's owners about key changes (docs/public-interface-design.md
# §4.4): creation, rotation, revocation, widened scopes and required
# rotation. Never includes the key itself.
class DevelopersMailer < ApplicationMailer
  SUBJECTS = {
    "created" => "A new Build Canada API key was created",
    "rotated" => "A Build Canada API key was rotated",
    "revoked" => "A Build Canada API key was revoked",
    "scopes_widened" => "A Build Canada API key was given more access",
    "rotation_required" => "Action needed: rotate your Build Canada API key"
  }.freeze

  default from: -> { (Rails.application.credentials.mailer || {}).fetch(:sender, "no-reply@buildcanada.com") }

  def key_changed
    @api_key = params.fetch(:api_key)
    @event = params.fetch(:event)
    recipients = @api_key.account.memberships.where(role: "owner").includes(:user).map { |m| m.user.email }
    return if recipients.empty?

    mail(to: recipients, subject: SUBJECTS.fetch(@event))
  end
end
