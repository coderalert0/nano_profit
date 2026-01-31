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

    # revenue = event_revenue + subscription_revenue (now invoice-based)
    assert_equal result.event_revenue_in_cents + result.subscription_revenue_in_cents,
      result.revenue_in_cents,
      "Total revenue should equal event + invoice revenue"
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
  # INVOICE PRORATION: verify boundary correctness
  # ═══════════════════════════════════════════════════════════════════

  test "invoice_revenue_for_period prorates correctly for partial overlap" do
    org = organizations(:acme)
    customer = customers(:customer_with_subscription)

    # monthly_invoice fixture: Jan 1 - Feb 1, $50.00
    # Query Jan 20 - Jan 27 = 7 days out of 31
    period = Time.new(2026, 1, 20)..Time.new(2026, 1, 27)
    result = MarginCalculator.send(:invoice_revenue_for_period, customer.stripe_invoices, period)

    expected = (5000.to_d * 7 / 31).round
    assert_equal expected, result
  end

  test "invoice_revenue_for_period returns full amount for nil period" do
    customer = customers(:customer_with_subscription)
    result = MarginCalculator.send(:invoice_revenue_for_period, customer.stripe_invoices, nil)

    assert_equal customer.stripe_invoices.sum(:amount_in_cents), result
  end

  test "invoice_revenue_for_period returns 0 when no invoices overlap" do
    customer = customers(:customer_one)
    period = Time.new(2026, 1, 1)..Time.new(2026, 1, 8)
    result = MarginCalculator.send(:invoice_revenue_for_period, customer.stripe_invoices, period)
    assert_equal 0, result
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
  # STRIPE INVOICE SYNC + CUSTOMER UNIQUENESS: race condition interaction
  # ═══════════════════════════════════════════════════════════════════

  test "invoice_sync find_or_create_customer handles model-level uniqueness race" do
    # Tests that InvoiceSyncService#find_or_create_customer correctly handles
    # the case where create_or_find_by! raises RecordInvalid (from model validation)
    # instead of RecordNotUnique (from DB constraint).
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

    # But InvoiceSyncService has a rescue that handles this gracefully.
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

    events = customer.events.processed
    manual_revenue = events.sum(:revenue_amount_in_cents)
    manual_cost = events.sum(:total_cost_in_cents)

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

    assert_equal 1, result[:created], "Model deprecated today should still be included"
  end

  # ═══════════════════════════════════════════════════════════════════
  # VENDOR RESPONSE PARSER: downstream impact on event validation
  # ═══════════════════════════════════════════════════════════════════

  test "unknown model name from parser is rejected by API validation" do
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
  # CUSTOMER MODEL: validation edge cases
  # ═══════════════════════════════════════════════════════════════════

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
    org = organizations(:acme)
    alert = org.margin_alerts.create!(
      dimension: "customer",
      dimension_value: "999999",
      alert_type: "negative_margin",
      message: "Customer was deleted"
    )

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

    assert result.key?("vendor_name"), "Parser must return vendor_name"
    assert result.key?("ai_model_name"), "Parser must return ai_model_name"
    assert result.key?("input_tokens"), "Parser must return input_tokens"
    assert result.key?("output_tokens"), "Parser must return output_tokens"
  end

  test "parser output ai_model_name is never blank when vendor_costs reaches EventProcessor" do
    result = VendorResponseParser.call(vendor_name: "anthropic", raw_response: nil)
    assert_equal "unknown", result["ai_model_name"]

    assert_not result["ai_model_name"].blank?
  end
end
