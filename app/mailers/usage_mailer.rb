# Usage emails for the public data API: quota warnings to an account's
# owners (design §6.2, once each at 80% and 100% of the monthly quota), and
# reconciliation alerts to staff (§6.3).
class UsageMailer < ApplicationMailer
  default from: -> { (Rails.application.credentials.mailer || {}).fetch(:sender, "no-reply@buildcanada.com") }

  def quota_warning
    @account = params.fetch(:account)
    @threshold = params.fetch(:threshold)
    @used = params.fetch(:used)
    @quota = params.fetch(:quota)
    @resets_at = params.fetch(:resets_at)
    recipients = @account.memberships.where(role: "owner").includes(:user).map { |m| m.user.email }
    return if recipients.empty?

    subject = if @threshold >= 100
      "Your Build Canada API quota is used up for this month"
    else
      "You've used #{@threshold}% of your Build Canada API quota"
    end
    mail(to: recipients, subject:)
  end

  # Staff: the rollup and the edge disagree on some accounts' daily units.
  def reconcile_drift
    @reconciliations = params.fetch(:reconciliations)
    recipients = self.class.staff_recipients
    return if recipients.empty?

    mail(to: recipients, subject: "Usage reconciliation: #{@reconciliations.size} account-days drifted over 0.5%")
  end

  # USAGE_ALERT_EMAILS / credentials usage.alert_emails (comma-separated), or
  # the superadmins.
  def self.staff_recipients
    configured = ENV["USAGE_ALERT_EMAILS"].presence || Rails.application.credentials.dig(:usage, :alert_emails).presence
    return configured.to_s.split(",").map(&:strip).compact_blank if configured

    User.where(role: "superadmin").pluck(:email)
  end
end
