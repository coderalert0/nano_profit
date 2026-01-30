require "test_helper"

class UsageTelemetryEventTest < ActiveSupport::TestCase
  test "requires unique_request_token" do
    event = UsageTelemetryEvent.new(unique_request_token: nil)
    assert_not event.valid?
    assert_includes event.errors[:unique_request_token], "can't be blank"
  end

  test "unique_request_token enforced unique by DB constraint" do
    existing = usage_telemetry_events(:processed_event)
    dup = UsageTelemetryEvent.new(
      organization: existing.organization,
      unique_request_token: existing.unique_request_token,
      customer_external_id: "cust_001",
      event_type: "test",
      revenue_amount_in_cents: 100
    )
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
  end

  test "revenue_amount_in_cents must be non-negative" do
    event = UsageTelemetryEvent.new(
      organization: organizations(:acme),
      unique_request_token: "req_neg_rev",
      customer_external_id: "cust_001",
      event_type: "test",
      revenue_amount_in_cents: -100
    )
    assert_not event.valid?
    assert_includes event.errors[:revenue_amount_in_cents], "must be greater than or equal to 0"
  end

  test "scopes work correctly" do
    assert_includes UsageTelemetryEvent.processed, usage_telemetry_events(:processed_event)
    assert_not_includes UsageTelemetryEvent.processed, usage_telemetry_events(:pending_event)
    assert_includes UsageTelemetryEvent.pending, usage_telemetry_events(:pending_event)
  end
end
