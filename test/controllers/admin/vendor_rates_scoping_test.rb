require "test_helper"

# Tests vendor rate org scoping security (Fix #3).
# Ensures admins only see their org's rates + global rates.
class Admin::VendorRatesScopingTest < ActionDispatch::IntegrationTest
  setup do
    @admin_session = sessions(:admin_session)
    @acme = organizations(:acme)

    # Create a second org with its own rate
    @rival = Organization.create!(name: "Rival Corp")
    @rival_rate = @rival.vendor_rates.create!(
      vendor_name: "rival_vendor",
      ai_model_name: "rival_model",
      input_rate_per_1k: 99.0,
      output_rate_per_1k: 99.0,
      unit_type: "tokens",
      active: true
    )
  end

  test "index does not show rates from other organizations" do
    get admin_vendor_rates_url, headers: auth_headers(@admin_session)
    assert_response :success

    # Should NOT see rival's rate
    assert_select "td", text: "rival_vendor", count: 0
    assert_select "td", text: "rival_model", count: 0
  end

  test "index shows global rates (organization_id nil)" do
    get admin_vendor_rates_url, headers: auth_headers(@admin_session)
    assert_response :success

    # Global openai rate should be visible
    assert_select "td", text: "openai"
  end

  test "index shows own org rates" do
    get admin_vendor_rates_url, headers: auth_headers(@admin_session)
    assert_response :success

    # Acme's org-specific rate should be visible (gpt-4 acme override)
    assert_select "td", text: "gpt-4"
  end

  test "cannot edit rate from another organization" do
    get edit_admin_vendor_rate_url(@rival_rate), headers: auth_headers(@admin_session)
    assert_response :not_found
  end

  test "cannot update rate from another organization" do
    patch admin_vendor_rate_url(@rival_rate), params: {
      vendor_rate: { input_rate_per_1k: 0.0001 }
    }, headers: auth_headers(@admin_session)
    assert_response :not_found

    # Rate should be unchanged
    assert_equal BigDecimal("99.0"), @rival_rate.reload.input_rate_per_1k
  end

  test "cannot delete rate from another organization" do
    delete admin_vendor_rate_url(@rival_rate), headers: auth_headers(@admin_session)
    assert_response :not_found

    assert VendorRate.exists?(@rival_rate.id), "Rival's rate should still exist"
  end

  test "cannot inject organization_id via params" do
    post admin_vendor_rates_url, params: {
      vendor_rate: {
        vendor_name: "sneaky",
        ai_model_name: "injection_test",
        input_rate_per_1k: 1.0,
        output_rate_per_1k: 1.0,
        unit_type: "tokens",
        active: true,
        organization_id: @rival.id  # should be filtered out
      }
    }, headers: auth_headers(@admin_session)

    created = VendorRate.find_by(ai_model_name: "injection_test")
    if created
      assert_not_equal @rival.id, created.organization_id,
        "Should not be able to set organization_id to rival org via params"
    end
  end

  test "vendor filter dropdown only shows vendors from own org and global" do
    get admin_vendor_rates_url, headers: auth_headers(@admin_session)
    assert_response :success

    # rival_vendor should not appear in filter options
    assert_no_match(/rival_vendor/, response.body)
  end

  private

  def auth_headers(session)
    { "Cookie" => "session_id=#{sign_cookie(session.id)}" }
  end

  def sign_cookie(value)
    cookies_jar = ActionDispatch::Request.new(Rails.application.env_config.merge("REQUEST_METHOD" => "GET")).cookie_jar
    cookies_jar.signed[:session_id] = value
    cookies_jar[:session_id]
  end
end
