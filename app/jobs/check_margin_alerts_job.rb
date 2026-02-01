class CheckMarginAlertsJob < ApplicationJob
  queue_as :default

  def perform(organization_id)
    org = Organization.find(organization_id)
    threshold_bps = org.margin_alert_threshold_bps
    return if threshold_bps <= 0

    period = org.margin_alert_period_days.days.ago..Time.current

    check_event_type_margins(org, period, threshold_bps)
    check_customer_margins(org, period, threshold_bps)
  end

  private

  def check_event_type_margins(org, period, threshold_bps)
    MarginCalculator.event_type_margins(org, period).each do |etm|
      margin = etm[:margin]
      create_alert(org, "event_type", etm[:event_type], margin, threshold_bps)
    end
  end

  def check_customer_margins(org, period, threshold_bps)
    MarginCalculator.customer_margins(org, period).each do |cm|
      margin = cm[:margin]
      label = cm[:customer_name] || cm[:customer_external_id] || cm[:customer_id].to_s
      create_alert(org, "customer", cm[:customer_id].to_s, margin, threshold_bps, label: label)
    end
  end

  def create_alert(org, dimension, dimension_value, margin, threshold_bps, label: nil)
    # Skip zero-activity dimensions to avoid false positives
    return if margin.revenue_in_cents.zero? && margin.cost_in_cents.zero?

    display_label = label || dimension_value

    if margin.margin_in_cents.negative?
      create_alert_unless_duplicate(org, dimension, dimension_value, "negative_margin",
        build_message(dimension, display_label, margin, org))
    elsif margin.margin_bps < threshold_bps
      create_alert_unless_duplicate(org, dimension, dimension_value, "below_threshold",
        build_message(dimension, display_label, margin, org))
    end
  end

  def build_message(dimension, label, margin, org)

    if margin.margin_in_cents.negative?
      "Negative margin on #{dimension.humanize.downcase} \"#{label}\": #{margin.margin_in_cents} cents"
    else
      "Margin #{margin.margin_bps} bps on #{dimension.humanize.downcase} \"#{label}\" (threshold: #{org.margin_alert_threshold_bps} bps)"
    end
  end

  def create_alert_unless_duplicate(org, dimension, dimension_value, alert_type, message)
    alert = MarginAlert.create!(
      organization: org,
      dimension: dimension,
      dimension_value: dimension_value,
      alert_type: alert_type,
      message: message
    )
    AlertMailer.margin_alert(alert).deliver_later
  rescue ActiveRecord::RecordNotUnique
    # Already have an unacknowledged alert for this dimension/value/type
  end
end
