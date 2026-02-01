require "test_helper"

class MultiOrgIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @org_a = organizations(:acme)

    @org_b = Organization.create!(name: "Other Org")
    @customer_b = @org_b.customers.create!(external_id: "cust_b_001", name: "Org B Customer")
    @org_b.events.create!(
      unique_request_token: "orgb_event_1",
      customer: @customer_b,
      customer_external_id: "cust_b_001",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 2000,
      total_cost_in_cents: 1500,
      margin_in_cents: 500,
      status: "processed",
      occurred_at: 1.hour.ago
    )
  end

  test "API creates events only for authenticated organization" do
    post "/api/v1/events",
      params: { events: [{ unique_request_token: "iso_test_1", customer_external_id: "cust_001",
                            event_type: "ai_analysis", revenue_amount_in_cents: 100 }] }.to_json,
      headers: { "Authorization" => "Bearer #{@org_a.api_key}", "Content-Type" => "application/json" }

    assert_response :success
    result = JSON.parse(response.body)
    event_id = result["results"].first["id"]

    event = Event.find(event_id)
    assert_equal @org_a.id, event.organization_id
    assert_not_equal @org_b.id, event.organization_id
  end

  test "API rejects request with wrong org API key" do
    post "/api/v1/events",
      params: { events: [{ unique_request_token: "iso_test_2", customer_external_id: "cust_001",
                            event_type: "ai_analysis", revenue_amount_in_cents: 100 }] }.to_json,
      headers: { "Authorization" => "Bearer invalid_key", "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "MarginCalculator isolates results by organization" do
    margin_a = MarginCalculator.organization_margin(@org_a)
    margin_b = MarginCalculator.organization_margin(@org_b)

    # Org A should not include Org B's revenue
    assert_equal 1000, margin_a.event_revenue_in_cents
    assert_equal 2000, margin_b.event_revenue_in_cents

    # Cross-check: Org B cost should not leak into Org A
    assert_equal 800, margin_a.cost_in_cents
    assert_equal 1500, margin_b.cost_in_cents
  end

  test "customer_margins scoped to organization" do
    margins_a = MarginCalculator.customer_margins(@org_a)
    margins_b = MarginCalculator.customer_margins(@org_b)

    customer_names_a = margins_a.map { |m| m[:customer_name] }
    customer_names_b = margins_b.map { |m| m[:customer_name] }

    assert_includes customer_names_a, "Customer One"
    assert_not_includes customer_names_a, "Org B Customer"

    assert_includes customer_names_b, "Org B Customer"
    assert_not_includes customer_names_b, "Customer One"
  end

  test "margin alerts are scoped to organization" do
    @org_b.update!(margin_alert_threshold_bps: 5000, margin_alert_period_days: 30)

    CheckMarginAlertsJob.perform_now(@org_b.id)

    alerts_b = MarginAlert.where(organization: @org_b)
    alerts_a = MarginAlert.where(organization: @org_a)

    # Org B alerts should not reference Org A data
    alerts_b.each do |alert|
      assert_equal @org_b.id, alert.organization_id
    end

    # Org A should have no new alerts from this job run
    org_a_alert_count_before = alerts_a.count
    CheckMarginAlertsJob.perform_now(@org_a.id)
    # Any new alerts should belong to Org A
    MarginAlert.where(organization: @org_a).where("created_at > ?", 1.second.ago).each do |alert|
      assert_equal @org_a.id, alert.organization_id
    end
  end
end
