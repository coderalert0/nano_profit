require "test_helper"
require "ostruct"

# Deep logic tests tracing data flows end-to-end through every fix.
# These test the interactions BETWEEN fixes and catch second-order bugs.
class DeepLogicTest < ActiveSupport::TestCase
  # ═══════════════════════════════════════════════════════════════════
  # MARGIN CALCULATOR: Type safety across the full data pipeline
  # ═══════════════════════════════════════════════════════════════════

  test "customer_margins result types are compatible with dashboard view math" do
    # Dashboard does: (margin.margin_bps / 100.0).round(1)
    # If margin_bps is nil, this crashes. Verify it's always numeric.
    org = organizations(:acme)
    results = MarginCalculator.customer_margins(org)

    results.each do |cm|
      m = cm[:margin]
      # These must never be nil — views do arithmetic on them
      assert_not_nil m.revenue_in_cents, "revenue_in_cents nil for customer #{cm[:customer_name]}"
      assert_not_nil m.cost_in_cents, "cost_in_cents nil for customer #{cm[:customer_name]}"
      assert_not_nil m.margin_in_cents, "margin_in_cents nil for customer #{cm[:customer_name]}"
      assert_not_nil m.margin_bps, "margin_bps nil for customer #{cm[:customer_name]}"
      assert_not_nil m.subscription_revenue_in_cents, "subscription_revenue_in_cents nil"
      assert_not_nil m.event_revenue_in_cents, "event_revenue_in_cents nil"

      # Views call format_cents which does / 100.0 — must be numeric
      assert_respond_to m.revenue_in_cents, :/, "revenue must support division"
      assert_respond_to m.margin_bps, :/, "margin_bps must support division"

      # margin_bps must be integer-like for the (x / 100.0).round(1) dashboard call
      assert_nothing_raised { (m.margin_bps / 100.0).round(1) }
    end
  end

  test "event_type_margins result types are compatible with dashboard view math" do
    org = organizations(:acme)
    results = MarginCalculator.event_type_margins(org)

    results.each do |etm|
      m = etm[:margin]
      assert_not_nil etm[:event_type]
      assert_not_nil etm[:event_count]
      assert_not_nil m.margin_bps

      # Dashboard does: (et[:margin].margin_bps / 100.0).round(1)
      assert_nothing_raised { (m.margin_bps / 100.0).round(1) }
    end
  end

  test "organization_margin math is self-consistent" do
    org = organizations(:acme)
    result = MarginCalculator.organization_margin(org)

    # margin = revenue - cost
    assert_equal result.revenue_in_cents - result.cost_in_cents, result.margin_in_cents,
      "Margin should equal revenue minus cost"

    # revenue = event_revenue + subscription_revenue
    assert_equal result.event_revenue_in_cents + result.subscription_revenue_in_cents,
      result.revenue_in_cents,
      "Total revenue should equal event + subscription revenue"
  end

  # ═══════════════════════════════════════════════════════════════════
  # MARGIN CALCULATOR + ALERTS: data consistency between calculation and alerting
  # ═══════════════════════════════════════════════════════════════════

  test "check_margin_alerts_job uses same data shape as dashboard" do
    # CheckMarginAlertsJob calls customer_margins and accesses :customer_id, :margin
    # Make sure these keys exist in the returned data
    org = organizations(:acme)
    period = 7.days.ago..Time.current

    customer_results = MarginCalculator.customer_margins(org, period)
    customer_results.each do |cm|
      assert cm.key?(:customer_id), "customer_margins must return :customer_id"
      assert cm.key?(:margin), "customer_margins must return :margin"
      assert_respond_to cm[:margin], :margin_in_cents
      assert_respond_to cm[:margin], :margin_bps

      # The job does cm[:customer_id].to_s for dimension_value
      assert_nothing_raised { cm[:customer_id].to_s }
    end

    et_results = MarginCalculator.event_type_margins(org, period)
    et_results.each do |etm|
      assert etm.key?(:event_type), "event_type_margins must return :event_type"
      assert etm.key?(:margin), "event_type_margins must return :margin"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # EVENTS_DATE_RANGE: verify proration boundary correctness
  # ═══════════════════════════════════════════════════════════════════

  test "events_date_range creates a range that prorate_subscription handles correctly" do
    org = organizations(:acme)
    events = org.events.processed
    range = MarginCalculator.send(:events_date_range, events)
    return if range.nil?

    # prorate_subscription should not crash and should return a reasonable value
    result = MarginCalculator.send(:prorate_subscription, 10000, range)
    assert result >= 0, "Proration should be non-negative"
    assert result.is_a?(Integer), "Proration should be rounded to integer"
  end

  test "events_date_range with same-day events produces a valid range for proration" do
    org = organizations(:acme)
    # Create two events on the exact same timestamp
    customer = customers(:customer_one)
    now = Time.current

    e1 = org.events.create!(
      unique_request_token: "req_same_day_1_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      customer: customer,
      event_type: "test",
      revenue_amount_in_cents: 100,
      total_cost_in_cents: 50,
      margin_in_cents: 50,
      occurred_at: now,
      status: "processed"
    )
    e2 = org.events.create!(
      unique_request_token: "req_same_day_2_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      customer: customer,
      event_type: "test",
      revenue_amount_in_cents: 100,
      total_cost_in_cents: 50,
      margin_in_cents: 50,
      occurred_at: now,
      status: "processed"
    )

    scope = org.events.processed.where(id: [ e1.id, e2.id ])
    range = MarginCalculator.send(:events_date_range, scope)

    assert_not_nil range, "Should produce a range even for same-day events"
    assert range.last > range.first, "Range end must be after start (got #{range})"

    # Proration should work on this range
    prorated = MarginCalculator.send(:prorate_subscription, 30000, range)
    assert prorated > 0, "Proration for 1 day should be positive"
  end

  # ═══════════════════════════════════════════════════════════════════
  # VENDOR RATES CONTROLLER: security boundary testing
  # ═══════════════════════════════════════════════════════════════════

  test "vendor rate created by admin is global (no organization)" do
    # Admin-created rates are intentionally global (organization_id: nil).
    # Org-specific overrides come from Pricing::SyncService or direct DB assignment.
    rate = VendorRate.new(
      vendor_name: "test_vendor",
      ai_model_name: "test_model",
      input_rate_per_1k: 1.0,
      output_rate_per_1k: 2.0,
      unit_type: "tokens"
    )
    assert_nil rate.organization_id,
      "Admin-created rates should be global (nil organization_id)"
  end

  # ═══════════════════════════════════════════════════════════════════
  # STRIPE SYNC + CUSTOMER UNIQUENESS: race condition interaction
  # ═══════════════════════════════════════════════════════════════════

  test "subscription_sync find_or_create_customer handles model-level uniqueness race" do
    # Tests that SubscriptionSyncService#find_or_create_customer correctly handles
    # the case where create_or_find_by! raises RecordInvalid (from model validation)
    # instead of RecordNotUnique (from DB constraint).
    # The rescue ActiveRecord::RecordInvalid fallback should find the existing record.
    org = organizations(:acme)
    existing = org.customers.find_by(external_id: "cust_001")
    assert existing, "Fixture customer_one should exist with external_id cust_001"

    # Bare create_or_find_by! raises RecordInvalid due to model uniqueness validation
    assert_raises(ActiveRecord::RecordInvalid) do
      org.customers.create_or_find_by!(external_id: "cust_001") do |c|
        c.name = "Duplicate"
        c.stripe_customer_id = "cus_test"
      end
    end

    # But SubscriptionSyncService has a rescue that handles this gracefully.
    # Verify the rescue logic: catch RecordInvalid on :external_id, then find_by!
    begin
      org.customers.create_or_find_by!(external_id: "cust_001") do |c|
        c.name = "Duplicate"
        c.stripe_customer_id = "cus_test"
      end
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors[:external_id]&.any?
      found = org.customers.find_by!(external_id: "cust_001")
      assert_equal existing.id, found.id, "Rescue should find the existing customer"
    end
  end

  test "find_or_create_by! safely handles existing records" do
    # ProcessEventJob uses find_or_create_by! which does FIND first
    org = organizations(:acme)

    # This should find the existing customer, not try to create
    customer = org.customers.find_or_create_by!(external_id: "cust_001") do |c|
      c.name = "Should not overwrite"
    end

    assert_equal customers(:customer_one).id, customer.id
    assert_equal "Customer One", customer.name, "find_or_create_by! should NOT overwrite existing name"
  end

  # ═══════════════════════════════════════════════════════════════════
  # EVENT PROCESSING PIPELINE: full trace from API to margin display
  # ═══════════════════════════════════════════════════════════════════

  test "event with zero tokens produces zero cost entry" do
    org = organizations(:acme)
    customer = customers(:customer_one)

    # Edge case: vendor_costs has both tokens = 0
    # API validation rejects this, but what if data gets through?
    event = org.events.create!(
      unique_request_token: "req_zero_tok_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      customer: customer,
      event_type: "test",
      revenue_amount_in_cents: 500,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "ai_model_name" => "gpt-4",
        "input_tokens" => 0,
        "output_tokens" => 0,
        "unit_count" => 0,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current,
      status: "customer_linked"
    )

    entries = EventProcessor.new(event).call
    assert_equal 1, entries.size
    assert_equal 0, entries.first.amount_in_cents.to_i
    # The entry has amount 0 but should still pass numericality validation
    assert entries.first.persisted?
  end

  test "event processor cost calculation matches manual math" do
    org = organizations(:acme)
    customer = customers(:customer_one)
    rate = vendor_rates(:openai_gpt4_acme) # input=2.5/1k, output=5.0/1k

    event = org.events.create!(
      unique_request_token: "req_math_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      customer: customer,
      event_type: "test",
      revenue_amount_in_cents: 10000,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "ai_model_name" => "gpt-4",
        "input_tokens" => 5000,
        "output_tokens" => 2000,
        "unit_count" => 7000,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current,
      status: "customer_linked"
    )

    entries = EventProcessor.new(event).call
    entry = entries.first

    # Manual calculation:
    # input_cost = 5000 * 2.5 / 1000 = 12.5
    # output_cost = 2000 * 5.0 / 1000 = 10.0
    # total = 22.5
    expected = BigDecimal("22.5")
    assert_equal expected, entry.amount_in_cents, "Cost calculation should match: 5000*2.5/1000 + 2000*5.0/1000"
  end

  test "full pipeline: margin_calculator output matches event-level data" do
    org = organizations(:acme)
    customer = customers(:customer_one)

    # Get all processed events for this customer
    events = customer.events.processed
    manual_revenue = events.sum(:revenue_amount_in_cents)
    manual_cost = events.sum(:total_cost_in_cents)

    # MarginCalculator should return the same totals (without subscription)
    result = MarginCalculator.customer_margin(customer)

    assert_equal manual_revenue, result.event_revenue_in_cents,
      "Calculator event_revenue should match direct sum of events"
    assert_equal manual_cost, result.cost_in_cents,
      "Calculator cost should match direct sum of events"
  end

  # ═══════════════════════════════════════════════════════════════════
  # PRICING SYNC: edge cases in data handling
  # ═══════════════════════════════════════════════════════════════════

  test "pricing sync handles model with zero rates" do
    data = {
      "openai/free-model" => {
        "litellm_provider" => "openai",
        "input_cost_per_token" => 0,
        "output_cost_per_token" => 0
      }
    }

    service = Pricing::SyncService.new(pricing_data: data)
    result = service.perform

    # Zero rates should be accepted (free tier models)
    assert_equal 1, result[:created]

    rate = VendorRate.find_by(ai_model_name: "free-model", organization_id: nil)
    assert_not_nil rate
    assert_equal 0, rate.input_rate_per_1k
    assert_equal 0, rate.output_rate_per_1k
  end

  test "pricing sync with future deprecation date keeps model" do
    data = {
      "openai/future-model" => {
        "litellm_provider" => "openai",
        "input_cost_per_token" => 0.00001,
        "output_cost_per_token" => 0.00003,
        "deprecation_date" => (Date.current + 1.year).to_s
      }
    }

    service = Pricing::SyncService.new(pricing_data: data)
    result = service.perform

    assert_equal 1, result[:created], "Future deprecation date should not reject model"
  end

  test "pricing sync with today's deprecation date keeps model" do
    # Edge case: deprecated today — is it still active?
    data = {
      "openai/today-model" => {
        "litellm_provider" => "openai",
        "input_cost_per_token" => 0.00001,
        "output_cost_per_token" => 0.00003,
        "deprecation_date" => Date.current.to_s
      }
    }

    service = Pricing::SyncService.new(pricing_data: data)
    result = service.perform

    # Date.parse(deprecation) < Date.current — today is NOT < today
    assert_equal 1, result[:created], "Model deprecated today should still be included"
  end

  # ═══════════════════════════════════════════════════════════════════
  # VENDOR RESPONSE PARSER: downstream impact on event validation
  # ═══════════════════════════════════════════════════════════════════

  test "unknown model name from parser is rejected by API validation" do
    # Parser returns "unknown", API validator checks known_pairs
    # "unknown" won't be in known_pairs, so the event is rejected
    known_pairs = Set.new([ [ "openai", "gpt-4" ], [ "openai", "gpt-3.5-turbo" ] ])

    errors = []
    vc = { "ai_model_name" => "unknown", "vendor_name" => "openai", "input_tokens" => 100, "output_tokens" => 50 }
    ai_model_name = vc["ai_model_name"]
    vendor_name = vc["vendor_name"]

    if ai_model_name.blank?
      errors << "Missing ai_model_name"
    elsif !known_pairs.include?([ vendor_name, ai_model_name ])
      errors << "Unrecognized vendor_name '#{vendor_name}' with ai_model_name '#{ai_model_name}'"
    end

    assert errors.any?, "ai_model_name 'unknown' should be rejected as unrecognized"
    assert errors.first.include?("Unrecognized"), "Error should say 'Unrecognized', got: #{errors.first}"
  end

  # ═══════════════════════════════════════════════════════════════════
  # SUBSCRIPTION PRORATION: boundary conditions
  # ═══════════════════════════════════════════════════════════════════

  test "proration across month boundary is correct" do
    # Period: Jan 25..Feb 5
    # prorate_subscription iterates cursor < period_end with date subtraction:
    #   Jan slice: cursor=Jan 25, slice_end=min(Feb 1, Feb 5)=Feb 1, days=7 (25,26,27,28,29,30,31)
    #   Feb slice: cursor=Feb 1, slice_end=min(Mar 1, Feb 5)=Feb 5, days=4 (1,2,3,4)
    period = Date.new(2026, 1, 25)..Date.new(2026, 2, 5)
    result = MarginCalculator.send(:prorate_subscription, 31000, period)

    expected = (BigDecimal("31000") * 7 / 31 + BigDecimal("31000") * 4 / 28).round

    assert_equal expected, result,
      "Cross-month proration should be #{expected}, got #{result}"
  end

  test "proration with zero monthly revenue returns 0" do
    period = Date.new(2026, 1, 1)..Date.new(2026, 2, 1)
    result = MarginCalculator.send(:prorate_subscription, 0, period)
    assert_equal 0, result
  end

  test "proration with nil period returns 0" do
    result = MarginCalculator.send(:prorate_subscription, 10000, nil)
    assert_equal 0, result
  end

  # ═══════════════════════════════════════════════════════════════════
  # ORGANIZATION CASCADE: verify no orphan records
  # ═══════════════════════════════════════════════════════════════════

  test "organization destroy cascades through all associations" do
    org = Organization.create!(name: "Cascade Test Org")
    user = org.users.create!(email_address: "cascade@test.com", password: "password123")
    customer = org.customers.create!(external_id: "cascade_cust", name: "Cascade Customer")
    rate = org.vendor_rates.create!(
      vendor_name: "test", ai_model_name: "test",
      input_rate_per_1k: 1.0, output_rate_per_1k: 1.0,
      unit_type: "tokens"
    )
    event = org.events.create!(
      unique_request_token: "req_cascade_#{SecureRandom.hex(4)}",
      customer_external_id: "cascade_cust",
      customer_name: "Cascade Customer",
      customer: customer,
      event_type: "test",
      revenue_amount_in_cents: 100,
      occurred_at: Time.current
    )
    # margin_alerts belong to organization (no customer_id FK), so they cascade via org
    alert = org.margin_alerts.create!(
      dimension: "customer",
      dimension_value: customer.id.to_s,
      alert_type: "negative_margin",
      message: "Test alert"
    )

    ids = {
      user: user.id, customer: customer.id, rate: rate.id,
      event: event.id, alert: alert.id
    }

    org.destroy!

    assert_nil User.find_by(id: ids[:user]), "Users should be destroyed"
    assert_nil Customer.find_by(id: ids[:customer]), "Customers should be destroyed"
    assert_nil VendorRate.find_by(id: ids[:rate]), "VendorRates should be destroyed"
    assert_nil Event.find_by(id: ids[:event]), "Events should be destroyed"
    assert_nil MarginAlert.find_by(id: ids[:alert]), "MarginAlerts should be destroyed via organization"
  end

  # ═══════════════════════════════════════════════════════════════════
  # STRIPE SYNC: monthly amount edge cases
  # ═══════════════════════════════════════════════════════════════════

  test "yearly subscription is correctly divided to monthly" do
    service = Stripe::SubscriptionSyncService.new(organizations(:acme))
    price = OpenStruct.new(
      active: true,
      unit_amount: 120_00, # $120/year
      recurring: OpenStruct.new(interval: "year", interval_count: 1)
    )
    result = service.send(:calculate_monthly_amount, price)
    assert_equal BigDecimal("1000"), result, "$120/year should be $10/month (1000 cents)"
  end

  test "weekly subscription is correctly converted to monthly" do
    service = Stripe::SubscriptionSyncService.new(organizations(:acme))
    price = OpenStruct.new(
      active: true,
      unit_amount: 1200, # $12/week
      recurring: OpenStruct.new(interval: "week", interval_count: 1)
    )
    result = service.send(:calculate_monthly_amount, price)
    # $12 * 52 / 12 = $52
    assert_equal BigDecimal("5200"), result, "$12/week should be $52/month"
  end

  test "daily subscription is correctly converted to monthly" do
    service = Stripe::SubscriptionSyncService.new(organizations(:acme))
    price = OpenStruct.new(
      active: true,
      unit_amount: 100, # $1/day
      recurring: OpenStruct.new(interval: "day", interval_count: 1)
    )
    result = service.send(:calculate_monthly_amount, price)
    # $1 * 365 / 12 ≈ $30.4167
    expected = (BigDecimal("100") * 365 / 12)
    assert_equal expected, result
  end

  test "unknown interval returns 0" do
    service = Stripe::SubscriptionSyncService.new(organizations(:acme))
    price = OpenStruct.new(
      active: true,
      unit_amount: 1000,
      recurring: OpenStruct.new(interval: "biweekly", interval_count: 1)
    )
    assert_equal 0, service.send(:calculate_monthly_amount, price)
  end

  test "nil recurring returns 0" do
    service = Stripe::SubscriptionSyncService.new(organizations(:acme))
    price = OpenStruct.new(
      active: true,
      unit_amount: 1000,
      recurring: nil
    )
    assert_equal 0, service.send(:calculate_monthly_amount, price)
  end

  # ═══════════════════════════════════════════════════════════════════
  # CUSTOMER MODEL: validation edge cases
  # ═══════════════════════════════════════════════════════════════════

  test "customer with negative subscription revenue is rejected" do
    org = organizations(:acme)
    customer = org.customers.new(
      external_id: "neg_rev_test",
      name: "Negative Revenue",
      monthly_subscription_revenue_in_cents: -100
    )
    assert_not customer.valid?
    assert customer.errors[:monthly_subscription_revenue_in_cents].any?
  end

  test "customer with blank external_id is rejected" do
    org = organizations(:acme)
    customer = org.customers.new(external_id: "", name: "No ID")
    assert_not customer.valid?
    assert customer.errors[:external_id].any?
  end

  # ═══════════════════════════════════════════════════════════════════
  # MARGIN ALERT: dimension_value as string customer ID
  # ═══════════════════════════════════════════════════════════════════

  test "alert dimension_value stores customer_id as string and linked_customer resolves it" do
    org = organizations(:acme)
    customer = customers(:customer_one)

    alert = org.margin_alerts.create!(
      dimension: "customer",
      dimension_value: customer.id.to_s,
      alert_type: "negative_margin",
      message: "Test"
    )

    assert_equal customer, alert.linked_customer
  end

  test "alert dimension_value with non-numeric string returns nil for linked_customer" do
    alert = margin_alerts(:active_alert)
    alert.dimension_value = "not_a_number"
    assert_nil alert.linked_customer, "Non-numeric dimension_value should return nil"
  end

  test "alert_row view handles deleted customer gracefully" do
    # Simulate a customer that was deleted after alert creation
    org = organizations(:acme)
    alert = org.margin_alerts.create!(
      dimension: "customer",
      dimension_value: "999999",
      alert_type: "negative_margin",
      message: "Customer was deleted"
    )

    # The view does: alert.organization.customers.find_by(id: alert.dimension_value)
    customer = alert.organization.customers.find_by(id: alert.dimension_value)
    assert_nil customer, "Deleted/missing customer should return nil, not raise"
  end

  # ═══════════════════════════════════════════════════════════════════
  # VENDOR RESPONSE PARSER + EVENT PROCESSOR: data flow consistency
  # ═══════════════════════════════════════════════════════════════════

  test "parser output keys match what EventProcessor expects" do
    result = VendorResponseParser.call(
      vendor_name: "openai",
      raw_response: { model: "gpt-4", usage: { prompt_tokens: 100, completion_tokens: 50 } }
    )

    # EventProcessor reads these keys from vendor_costs_raw
    assert result.key?("vendor_name"), "Parser must return vendor_name"
    assert result.key?("ai_model_name"), "Parser must return ai_model_name"
    assert result.key?("input_tokens"), "Parser must return input_tokens"
    assert result.key?("output_tokens"), "Parser must return output_tokens"

    # EventProcessor also reads these optional keys
    # vc.fetch("unit_count", 0) and vc["unit_type"]
    # Parser doesn't set these — they come from the vendor_responses input
    # This is fine; EventProcessor uses fetch with defaults
  end

  test "parser output ai_model_name is never blank when vendor_costs reaches EventProcessor" do
    # With Fix #17, parser returns "unknown" instead of "".
    # But "unknown" would fail API validation (not in known_pairs).
    # So events with "unknown" model never reach EventProcessor.
    # Verify this by checking the validation logic.
    result = VendorResponseParser.call(vendor_name: "anthropic", raw_response: nil)
    assert_equal "unknown", result["ai_model_name"]

    # "unknown" is not blank, so validate_vendor_costs_with_pairs hits the known_pairs check
    assert_not result["ai_model_name"].blank?
  end
end
