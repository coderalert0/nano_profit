require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "requires unique_request_token" do
    event = Event.new(unique_request_token: nil)
    assert_not event.valid?
    assert_includes event.errors[:unique_request_token], "can't be blank"
  end

  test "unique_request_token enforced unique by DB constraint" do
    existing = events(:processed_event)
    dup = Event.new(
      organization: existing.organization,
      unique_request_token: existing.unique_request_token,
      customer_external_id: "cust_001",
      event_type: "test",
      revenue_amount_in_cents: 100
    )
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
  end

  test "revenue_amount_in_cents must be non-negative" do
    event = Event.new(
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
    assert_includes Event.processed, events(:processed_event)
    assert_not_includes Event.processed, events(:pending_event)
  end

  test "validates status inclusion" do
    event = Event.new(
      organization: organizations(:acme),
      unique_request_token: "req_bad_status",
      customer_external_id: "cust_001",
      event_type: "test",
      revenue_amount_in_cents: 100,
      status: "bogus"
    )
    assert_not event.valid?
    assert_includes event.errors[:status], "is not included in the list"
  end

  test "accepts valid statuses" do
    %w[pending customer_linked processed failed].each do |status|
      event = Event.new(
        organization: organizations(:acme),
        unique_request_token: "req_status_#{status}",
        customer_external_id: "cust_001",
        event_type: "test",
        revenue_amount_in_cents: 100,
        status: status
      )
      event.valid?
      assert_not_includes event.errors.attribute_names, :status, "Status '#{status}' should be valid"
    end
  end

  test "occurred_at cannot be more than 1 hour in the future" do
    event = Event.new(
      organization: organizations(:acme),
      unique_request_token: "req_future",
      customer_external_id: "cust_001",
      event_type: "test",
      revenue_amount_in_cents: 100,
      occurred_at: 2.hours.from_now
    )
    assert_not event.valid?
    assert_includes event.errors[:occurred_at], "cannot be more than 1 hour in the future"
  end

  test "occurred_at nil is allowed" do
    event = Event.new(
      organization: organizations(:acme),
      unique_request_token: "req_nil_time",
      customer_external_id: "cust_001",
      event_type: "test",
      revenue_amount_in_cents: 100,
      occurred_at: nil
    )
    event.valid?
    assert_not_includes event.errors.attribute_names, :occurred_at
  end

  test "occurred_at in the past is allowed" do
    event = Event.new(
      organization: organizations(:acme),
      unique_request_token: "req_past_time",
      customer_external_id: "cust_001",
      event_type: "test",
      revenue_amount_in_cents: 100,
      occurred_at: 1.day.ago
    )
    event.valid?
    assert_not_includes event.errors.attribute_names, :occurred_at
  end
end
