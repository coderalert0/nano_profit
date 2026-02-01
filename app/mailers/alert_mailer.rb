class AlertMailer < ApplicationMailer
  def margin_alert(alert)
    @alert = alert
    @organization = alert.organization

    recipients = @organization.users.where.not(email_verified_at: nil).pluck(:email_address)
    return if recipients.empty?

    mail(
      to: recipients,
      subject: "MarginDash Alert: #{alert.alert_type.humanize} — #{alert.dimension.humanize} #{alert.dimension_value}"
    )
  end
end
