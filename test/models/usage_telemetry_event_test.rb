require "test_helper"

class UsageTelemetryEventTest < ActiveSupport::TestCase
  test "requires unique_request_token" do
    event = UsageTelemetryEvent.new(unique_request_token: nil)
    assert_not event.valid?
    assert_includes event.errors[:unique_request_token], "can't be blank"
  end

  test "unique_request_token must be unique" do
    existing = usage_telemetry_events(:processed_event)
    dup = UsageTelemetryEvent.new(
      organization: existing.organization,
      unique_request_token: existing.unique_request_token,
      customer_external_id: "cust_001",
      event_type: "test",
      revenue_amount_in_cents: 100
    )
    assert_not dup.valid?
    assert_includes dup.errors[:unique_request_token], "has already been taken"
  end

  test "scopes work correctly" do
    assert_includes UsageTelemetryEvent.processed, usage_telemetry_events(:processed_event)
    assert_not_includes UsageTelemetryEvent.processed, usage_telemetry_events(:pending_event)
    assert_includes UsageTelemetryEvent.pending, usage_telemetry_events(:pending_event)
  end
end
