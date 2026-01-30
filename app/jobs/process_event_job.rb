class ProcessEventJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Event.find(event_id)

    link_customer(event) if event.status == "pending"
    process_costs(event) if event.status == "customer_linked"

    event.reload
    return unless event.status == "processed"

    check_margin_alerts(event)
    broadcast_update(event)
  rescue ActiveRecord::RecordNotFound
    # Event was deleted between enqueue and perform; nothing to do
  rescue RuntimeError => e
    event&.update_column(:status, "failed") if event&.persisted?
    raise
  rescue => e
    # Transient error — leave status unchanged so SolidQueue can retry
    raise
  end

  private

  def link_customer(event)
    ActiveRecord::Base.transaction do
      event.lock!
      return unless event.status == "pending"

      organization = event.organization

      customer = organization.customers.create_or_find_by!(
        external_id: event.customer_external_id
      ) do |c|
        c.name = event.customer_name
      end

      unless customer.organization_id == organization.id
        raise "Customer #{customer.id} organization mismatch: expected #{organization.id}, got #{customer.organization_id}"
      end

      event.update!(customer: customer, status: "customer_linked")
    end
  end

  def process_costs(event)
    ActiveRecord::Base.transaction do
      event.lock!
      return unless event.status == "customer_linked"

      EventProcessor.new(event).call

      total_cost = event.cost_entries.sum(:amount_in_cents)
      margin = event.revenue_amount_in_cents - total_cost

      event.update!(
        total_cost_in_cents: total_cost,
        margin_in_cents: margin,
        status: "processed"
      )
    end
  end

  def check_margin_alerts(event)
    org = event.organization
    threshold_bps = org.margin_alert_threshold_bps

    margin_cents = event.margin_in_cents.to_d
    revenue_cents = event.revenue_amount_in_cents.to_d

    if margin_cents.negative?
      create_alert_unless_duplicate(
        org, event.customer, "negative_margin",
        "Negative margin on event #{event.event_type} for customer #{event.customer&.name || event.customer_external_id}: #{margin_cents} cents"
      )
    elsif threshold_bps > 0 && revenue_cents > 0
      margin_bps = ((margin_cents * 10_000) / revenue_cents).to_i
      if margin_bps < threshold_bps
        create_alert_unless_duplicate(
          org, event.customer, "below_threshold",
          "Margin #{margin_bps} bps below threshold #{threshold_bps} bps on event #{event.event_type} for customer #{event.customer&.name || event.customer_external_id}"
        )
      end
    end
  end

  def create_alert_unless_duplicate(org, customer, alert_type, message)
    MarginAlert.create!(
      organization: org,
      customer: customer,
      alert_type: alert_type,
      message: message
    )
  rescue ActiveRecord::RecordNotUnique
    # Duplicate unacknowledged alert already exists (partial unique index)
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
