class ProcessUsageTelemetryJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = UsageTelemetryEvent.find(event_id)
    return if event.status == "processed"

    ActiveRecord::Base.transaction do
      organization = Organization.lock.find(event.organization_id)

      customer = organization.customers.create_or_find_by!(
        external_id: event.customer_external_id
      ) do |c|
        c.name = event.customer_name
      end

      raise ActiveRecord::Rollback if customer.organization_id != organization.id

      event.update!(customer: customer)

      Telemetry::Processor.new(event).call

      total_cost = event.cost_entries.sum(:amount_in_cents)
      margin = event.revenue_amount_in_cents - total_cost

      event.update!(
        total_cost_in_cents: total_cost,
        margin_in_cents: margin,
        status: "processed"
      )
    end

    event.reload
    return unless event.status == "processed"

    check_margin_alerts(event)
    broadcast_update(event)
  rescue ActiveRecord::RecordNotFound
    # Event was deleted between enqueue and perform; nothing to do
  rescue => e
    event&.update_column(:status, "failed") if event&.persisted?
    raise
  end

  private

  def check_margin_alerts(event)
    org = event.organization
    threshold_bps = org.margin_alert_threshold_bps

    margin_cents = event.margin_in_cents.to_i
    revenue_cents = event.revenue_amount_in_cents.to_i

    if margin_cents.negative?
      MarginAlert.create!(
        organization: org,
        customer: event.customer,
        alert_type: "negative_margin",
        message: "Negative margin on event #{event.event_type} for customer #{event.customer&.name || event.customer_external_id}: #{margin_cents} cents"
      )
    elsif threshold_bps > 0 && revenue_cents > 0
      margin_bps = (margin_cents * 10_000) / revenue_cents
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
