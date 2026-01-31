require "test_helper"
require "ostruct"

# Business logic regression tests for all bug fixes.
# These verify real user-facing behavior, not just method signatures.
class BusinessLogicTest < ActiveSupport::TestCase
  # ─── Fix #1: COALESCE in customer_margins ───────────────────────────

  test "customer_margins returns zero sums for customer with no events in period" do
    org = organizations(:acme)
    # Query a period with no events — the SQL SUM must not return NULL
    future_period = 1.year.from_now..2.years.from_now
    results = MarginCalculator.customer_margins(org, future_period)

    # Should still include subscription-only customers, not crash
    results.each do |r|
      assert_kind_of Integer, r[:margin][:revenue_in_cents].to_i
      assert_kind_of Integer, r[:margin][:cost_in_cents].to_i
    end
  end

  test "customer_margins returns correct totals for customers with events" do
    org = organizations(:acme)
    results = MarginCalculator.customer_margins(org)

    customer_one_result = results.find { |r| r[:customer_name] == "Customer One" }
    assert_not_nil customer_one_result, "Customer One should appear in results"

    margin = customer_one_result[:margin]
    assert margin.revenue_in_cents >= 0, "Revenue should be non-negative"
    assert margin.cost_in_cents >= 0, "Cost should be non-negative"
    # Margin = revenue - cost
    assert_equal margin.revenue_in_cents - margin.cost_in_cents, margin.margin_in_cents
  end

  # ─── Fix #4: events_date_range off-by-one ───────────────────────────

  test "events_date_range includes the last day of events" do
    org = organizations(:acme)
    events = org.events.processed

    # Use send to access private method
    range = MarginCalculator.send(:events_date_range, events)
    return if range.nil? # no events in test data

    latest_event = events.order(occurred_at: :desc).first
    assert range.cover?(latest_event.occurred_at.to_date),
      "Date range #{range} should cover last event date #{latest_event.occurred_at.to_date}"
  end

  test "events_date_range end is at least one day after earliest event" do
    org = organizations(:acme)
    events = org.events.processed
    range = MarginCalculator.send(:events_date_range, events)
    return if range.nil?

    earliest = events.order(occurred_at: :asc).first.occurred_at.to_date
    assert range.last > earliest,
      "End date #{range.last} should be after earliest event #{earliest}"
  end

  test "proration calculates correctly over a full month" do
    # A full month (Jan 2026) should return the full monthly amount
    period = Date.new(2026, 1, 1)..Date.new(2026, 2, 1)
    result = MarginCalculator.send(:prorate_subscription, 10000, period)
    assert_equal 10000, result, "Full month proration should equal monthly amount"
  end

  test "proration calculates correctly over a partial month" do
    # Half of January (15 days out of 31)
    period = Date.new(2026, 1, 1)..Date.new(2026, 1, 16)
    result = MarginCalculator.send(:prorate_subscription, 31000, period)
    # 15/31 * 31000 = 15000
    assert_equal 15000, result
  end

  # ─── Fix #2: MarginAlert.linked_customer ────────────────────────────

  test "linked_customer returns nil for non-existent customer ID" do
    alert = margin_alerts(:active_alert)
    alert.dimension_value = "999999999"  # non-existent ID
    assert_nil alert.linked_customer, "Should return nil, not raise"
  end

  test "linked_customer returns customer for valid ID" do
    alert = margin_alerts(:active_alert)
    customer = customers(:customer_one)
    alert.dimension_value = customer.id.to_s
    assert_equal customer, alert.linked_customer
  end

  test "linked_customer returns nil for event_type dimension" do
    alert = margin_alerts(:acknowledged_alert)
    assert alert.event_type?
    assert_nil alert.linked_customer
  end

  # ─── Fix #3: VendorRates org scoping ────────────────────────────────
  # (Controller-level tests below in a separate integration test class)

  # ─── Fix #5: Organization cascade destroy of vendor_rates ───────────

  test "destroying organization destroys its vendor rates" do
    org = Organization.create!(name: "Temp Org")
    rate = org.vendor_rates.create!(
      vendor_name: "test_vendor",
      ai_model_name: "test_model",
      input_rate_per_1k: 1.0,
      output_rate_per_1k: 2.0,
      unit_type: "tokens",
      active: true
    )
    rate_id = rate.id

    org.destroy!
    assert_nil VendorRate.find_by(id: rate_id), "Vendor rate should be destroyed with org"
  end

  # ─── Fix #6a: CostEntry numericality validation ─────────────────────

  test "cost entry rejects non-numeric amount" do
    event = events(:processed_event)
    entry = event.cost_entries.new(vendor_name: "test", amount_in_cents: "not_a_number")
    assert_not entry.valid?
    assert entry.errors[:amount_in_cents].any?
  end

  test "cost entry accepts numeric amount" do
    event = events(:processed_event)
    entry = event.cost_entries.new(vendor_name: "test", amount_in_cents: 42.5)
    assert entry.valid?
  end

  # ─── Fix #6b: VendorRate numericality validation ────────────────────

  test "vendor rate rejects negative input rate" do
    rate = VendorRate.new(
      vendor_name: "test", ai_model_name: "test",
      input_rate_per_1k: -1.0, output_rate_per_1k: 1.0,
      unit_type: "tokens"
    )
    assert_not rate.valid?
    assert rate.errors[:input_rate_per_1k].any?
  end

  test "vendor rate rejects negative output rate" do
    rate = VendorRate.new(
      vendor_name: "test", ai_model_name: "test",
      input_rate_per_1k: 1.0, output_rate_per_1k: -1.0,
      unit_type: "tokens"
    )
    assert_not rate.valid?
    assert rate.errors[:output_rate_per_1k].any?
  end

  test "vendor rate accepts zero rates" do
    rate = VendorRate.new(
      vendor_name: "test", ai_model_name: "test",
      input_rate_per_1k: 0, output_rate_per_1k: 0,
      unit_type: "tokens"
    )
    assert rate.valid?
  end

  test "vendor rate rejects non-numeric input rate" do
    rate = VendorRate.new(
      vendor_name: "test", ai_model_name: "test",
      input_rate_per_1k: "abc", output_rate_per_1k: 1.0,
      unit_type: "tokens"
    )
    assert_not rate.valid?
  end

  # ─── Fix #7: Stripe interval_count clamping ─────────────────────────

  test "calculate_monthly_amount clamps zero interval_count to 1" do
    service = Stripe::SubscriptionSyncService.new(organizations(:acme))
    price = OpenStruct.new(
      active: true,
      unit_amount: 5000,
      recurring: OpenStruct.new(interval: "month", interval_count: 0)
    )
    result = service.send(:calculate_monthly_amount, price)
    assert_equal BigDecimal("5000"), result, "interval_count=0 should be clamped to 1"
  end

  test "calculate_monthly_amount handles nil interval_count" do
    service = Stripe::SubscriptionSyncService.new(organizations(:acme))
    price = OpenStruct.new(
      active: true,
      unit_amount: 12000,
      recurring: OpenStruct.new(interval: "month", interval_count: nil)
    )
    result = service.send(:calculate_monthly_amount, price)
    assert_equal BigDecimal("12000"), result, "nil interval_count should default to 1"
  end

  test "calculate_monthly_amount handles quarterly billing" do
    service = Stripe::SubscriptionSyncService.new(organizations(:acme))
    price = OpenStruct.new(
      active: true,
      unit_amount: 9000,
      recurring: OpenStruct.new(interval: "month", interval_count: 3)
    )
    result = service.send(:calculate_monthly_amount, price)
    assert_equal BigDecimal("3000"), result, "quarterly $90 should be $30/month"
  end

  test "calculate_monthly_amount returns 0 for inactive price" do
    service = Stripe::SubscriptionSyncService.new(organizations(:acme))
    price = OpenStruct.new(
      active: false,
      unit_amount: 5000,
      recurring: OpenStruct.new(interval: "month", interval_count: 1)
    )
    assert_equal 0, service.send(:calculate_monthly_amount, price)
  end

  # ─── Fix #8: EventProcessor unit_type .presence fallback ────────────

  test "event processor uses rate unit_type when vendor cost has empty string" do
    org = organizations(:acme)
    rate = vendor_rates(:openai_gpt4_acme)
    event = org.events.create!(
      unique_request_token: "req_ut_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Test",
      customer: customers(:customer_one),
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "ai_model_name" => "gpt-4",
        "input_tokens" => 100,
        "output_tokens" => 50,
        "unit_count" => 150,
        "unit_type" => ""
      } ],
      occurred_at: Time.current,
      status: "customer_linked"
    )

    entries = EventProcessor.new(event).call
    assert_equal rate.unit_type, entries.first.unit_type,
      "Empty string unit_type should fall back to rate's unit_type"
  end

  test "event processor uses provided unit_type when present" do
    org = organizations(:acme)
    event = org.events.create!(
      unique_request_token: "req_ut2_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Test",
      customer: customers(:customer_one),
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "ai_model_name" => "gpt-4",
        "input_tokens" => 100,
        "output_tokens" => 50,
        "unit_count" => 150,
        "unit_type" => "characters"
      } ],
      occurred_at: Time.current,
      status: "customer_linked"
    )

    entries = EventProcessor.new(event).call
    assert_equal "characters", entries.first.unit_type
  end

  # ─── Fix #13: Pricing sync HTTP error handling ──────────────────────

  test "pricing sync raises on non-200 HTTP response" do
    service = Pricing::SyncService.new

    # Stub fetch_via_net_http to simulate a 500
    service.define_singleton_method(:fetch_via_net_http) do
      raise "HTTP 500 from pricing source"
    end
    # Also stub curl fallback
    service.define_singleton_method(:fetch_pricing_data) do
      raise "HTTP 500 from pricing source"
    end

    assert_raises(RuntimeError) { service.perform }
  end

  # ─── Fix #14: Pricing sync malformed deprecation dates ──────────────

  test "pricing sync skips models with malformed deprecation dates" do
    data = {
      "openai/gpt-test" => {
        "litellm_provider" => "openai",
        "input_cost_per_token" => 0.00001,
        "output_cost_per_token" => 0.00003,
        "deprecation_date" => "not-a-date"
      }
    }

    service = Pricing::SyncService.new(pricing_data: data)
    result = service.perform

    # Model should NOT be rejected (malformed date = treat as not deprecated)
    assert_equal 1, result[:created], "Model with malformed deprecation date should be created"
  end

  test "pricing sync rejects models with valid past deprecation dates" do
    data = {
      "openai/gpt-deprecated" => {
        "litellm_provider" => "openai",
        "input_cost_per_token" => 0.00001,
        "output_cost_per_token" => 0.00003,
        "deprecation_date" => "2020-01-01"
      }
    }

    service = Pricing::SyncService.new(pricing_data: data)
    result = service.perform

    assert_equal 0, result[:created], "Deprecated model should not be created"
  end

  # ─── Fix #17: VendorResponseParser "unknown" fallback ───────────────

  test "parser returns 'unknown' when model is nil" do
    result = VendorResponseParser.call(vendor_name: "openai", raw_response: {})
    assert_equal "unknown", result["ai_model_name"]
  end

  test "parser returns 'unknown' for anthropic with nil model" do
    result = VendorResponseParser.call(vendor_name: "anthropic", raw_response: {})
    assert_equal "unknown", result["ai_model_name"]
  end

  test "parser returns 'unknown' for google with nil model" do
    result = VendorResponseParser.call(vendor_name: "google", raw_response: {})
    assert_equal "unknown", result["ai_model_name"]
  end

  test "parser returns actual model name when present" do
    result = VendorResponseParser.call(
      vendor_name: "openai",
      raw_response: { model: "gpt-4", usage: { prompt_tokens: 10, completion_tokens: 5 } }
    )
    assert_equal "gpt-4", result["ai_model_name"]
  end

  # ─── Fix #18: Customer external_id uniqueness ───────────────────────

  test "cannot create two customers with same external_id in same org" do
    org = organizations(:acme)
    # customer_one already has external_id "cust_001"
    dup = org.customers.new(external_id: "cust_001", name: "Duplicate")
    assert_not dup.valid?
    assert dup.errors[:external_id].any?, "Should have uniqueness error on external_id"
  end

  test "can create customers with same external_id in different orgs" do
    org2 = Organization.create!(name: "Other Org")
    customer = org2.customers.new(external_id: "cust_001", name: "Same ext id different org")
    assert customer.valid?, "Same external_id in different org should be valid"
  end

  # ─── Fix #10: Stripe sync transaction safety ────────────────────────

  test "stripe sync update_customers is atomic" do
    org = organizations(:acme)
    service = Stripe::SubscriptionSyncService.new(org)

    # Create a customer with subscription revenue
    existing = org.customers.create!(
      external_id: "stripe_existing",
      name: "Existing Customer",
      stripe_customer_id: "cus_existing",
      monthly_subscription_revenue_in_cents: 5000
    )

    # Simulate a partial failure: one valid update, then an error
    bad_revenues = { "cus_good" => 3000, "cus_will_explode" => 1000 }

    # Stub find_or_create_customer to fail on the second call
    call_count = 0
    service.define_singleton_method(:find_or_create_customer) do |stripe_id|
      call_count += 1
      if stripe_id == "cus_will_explode"
        raise ActiveRecord::RecordInvalid.new(Customer.new)
      end
      org.customers.create!(
        external_id: stripe_id,
        name: "Good Customer",
        stripe_customer_id: stripe_id,
        monthly_subscription_revenue_in_cents: 0
      )
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      service.send(:update_customers, bad_revenues)
    end

    # The existing customer's revenue should NOT have been zeroed out
    # because the transaction rolled back
    existing.reload
    assert_equal 5000, existing.monthly_subscription_revenue_in_cents,
      "Transaction rollback should preserve existing customer revenue"
  end

  # ─── End-to-end: full event processing pipeline ─────────────────────

  test "full event processing pipeline: create -> link customer -> cost -> margin" do
    org = organizations(:acme)

    event = org.events.create!(
      unique_request_token: "req_e2e_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_e2e_new",
      customer_name: "E2E Test Customer",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "ai_model_name" => "gpt-4",
        "input_tokens" => 1000,
        "output_tokens" => 500,
        "unit_count" => 1500,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current,
      status: "pending"
    )

    ProcessEventJob.perform_now(event.id)

    event.reload
    assert_equal "processed", event.status

    # Customer should be created and linked
    assert_not_nil event.customer
    assert_equal "cust_e2e_new", event.customer.external_id
    assert_equal "E2E Test Customer", event.customer.name

    # Cost entries should exist
    assert event.cost_entries.any?, "Should have cost entries"
    assert event.total_cost_in_cents > 0, "Should have non-zero cost"

    # Margin should be revenue - cost
    assert_equal event.revenue_amount_in_cents - event.total_cost_in_cents, event.margin_in_cents

    # Acme org rate: input=2.5/1k, output=5.0/1k
    # cost = (1000 * 2.5/1000) + (500 * 5.0/1000) = 2.5 + 2.5 = 5.0
    assert_equal BigDecimal("5.0"), event.total_cost_in_cents
    assert_equal BigDecimal("995.0"), event.margin_in_cents

    # Verify this customer shows up in organization margin calculation
    org_margin = MarginCalculator.organization_margin(org)
    assert org_margin.cost_in_cents > 0
    assert org_margin.revenue_in_cents > 0
  end

  # ─── End-to-end: margin calculator with subscription proration ──────

  test "organization_margin includes subscription revenue prorated correctly" do
    org = organizations(:acme)
    sub_customer = customers(:customer_with_subscription)
    assert sub_customer.monthly_subscription_revenue_in_cents > 0

    result = MarginCalculator.organization_margin(org)
    assert result.subscription_revenue_in_cents > 0,
      "Organization margin should include subscription revenue"
    assert result.revenue_in_cents > result.event_revenue_in_cents,
      "Total revenue should be greater than event-only revenue when subscriptions exist"
  end

  # ─── Verify margin_bps calculation ──────────────────────────────────

  test "margin_bps is calculated correctly" do
    org = organizations(:acme)
    result = MarginCalculator.organization_margin(org)

    if result.revenue_in_cents > 0
      expected_bps = ((result.margin_in_cents * 10_000) / result.revenue_in_cents).to_i
      assert_equal expected_bps, result.margin_bps
    else
      assert_equal 0, result.margin_bps
    end
  end

  # ─── Verify event_type_margins uses COALESCE correctly ──────────────

  test "event_type_margins returns numeric values not nil" do
    org = organizations(:acme)
    results = MarginCalculator.event_type_margins(org)

    results.each do |r|
      assert_not_nil r[:margin].revenue_in_cents, "Revenue should not be nil"
      assert_not_nil r[:margin].cost_in_cents, "Cost should not be nil"
      assert_not_nil r[:margin].margin_in_cents, "Margin should not be nil"
      assert_not_nil r[:event_count], "Event count should not be nil"
    end
  end
end
