class ProcessUsageTelemetryJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = UsageTelemetryEvent.find(event_id)
    return if event.status == "processed"

    ActiveRecord::Base.transaction do
      customer = find_or_create_customer(event)
      event.update!(customer: customer)

      create_cost_entries(event)

      total_cost = event.cost_entries.sum(:amount_in_cents)
      margin = event.revenue_amount_in_cents - total_cost

      event.update!(
        total_cost_in_cents: total_cost,
        margin_in_cents: margin,
        status: "processed"
      )
    end

    check_margin_alerts(event.reload)
    broadcast_update(event)
  rescue => e
    event&.update(status: "failed") if event&.persisted?
    raise
  end

  private

  def find_or_create_customer(event)
    event.organization.customers.find_or_create_by!(
      external_id: event.customer_external_id
    ) do |customer|
      customer.name = event.customer_name
    end
  end

  def create_cost_entries(event)
    return if event.vendor_costs_raw.blank?

    event.vendor_costs_raw.each do |vc|
      event.cost_entries.create!(
        vendor_name: vc["vendor_name"],
        amount_in_cents: vc["amount_in_cents"],
        unit_count: vc["unit_count"],
        unit_type: vc["unit_type"]
      )
    end
  end

  def check_margin_alerts(event)
    org = event.organization
    threshold_bps = org.margin_alert_threshold_bps

    if event.margin_in_cents.negative?
      MarginAlert.create!(
        organization: org,
        customer: event.customer,
        alert_type: "negative_margin",
        message: "Negative margin on event #{event.event_type} for customer #{event.customer&.name || event.customer_external_id}: #{event.margin_in_cents} cents"
      )
    elsif threshold_bps > 0 && event.revenue_amount_in_cents > 0
      margin_bps = (event.margin_in_cents * 10_000) / event.revenue_amount_in_cents
      if margin_bps < threshold_bps
        MarginAlert.create!(
          organization: org,
          customer: event.customer,
          alert_type: "below_threshold",
          message: "Margin #{margin_bps} bps below threshold #{threshold_bps} bps on event #{event.event_type} for customer #{event.customer&.name || event.customer_external_id}"
        )
      end
    end
  end

  def broadcast_update(event)
    OrganizationChannel.broadcast_to(
      event.organization,
      {
        type: "event_processed",
        event_id: event.id,
        customer_name: event.customer&.name || event.customer_external_id,
        event_type: event.event_type,
        revenue_in_cents: event.revenue_amount_in_cents,
        cost_in_cents: event.total_cost_in_cents,
        margin_in_cents: event.margin_in_cents,
        occurred_at: event.occurred_at&.iso8601
      }
    )
  end
end
