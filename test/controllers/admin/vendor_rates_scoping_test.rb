require "test_helper"

# Tests vendor rate admin access.
# Admins are platform-wide and can see/manage ALL rates (global + org-specific).
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

  test "index shows rates from all organizations" do
    get admin_vendor_rates_url, headers: auth_headers(@admin_session)
    assert_response :success

    # Admin should see ALL rates including rival's
    assert_select "td", text: "rival_vendor"
    assert_select "td", text: "rival_model"
  end

  test "index shows global rates (organization_id nil)" do
    get admin_vendor_rates_url, headers: auth_headers(@admin_session)
    assert_response :success

    assert_select "td", text: "openai"
  end

  test "can edit rate from any organization" do
    get edit_admin_vendor_rate_url(@rival_rate), headers: auth_headers(@admin_session)
    assert_response :success
  end

  test "can update rate from any organization" do
    patch admin_vendor_rate_url(@rival_rate), params: {
      vendor_rate: { input_rate_per_1k: 0.0001 }
    }, headers: auth_headers(@admin_session)
    assert_redirected_to admin_vendor_rates_path

    assert_equal BigDecimal("0.0001"), @rival_rate.reload.input_rate_per_1k
  end

  test "can delete rate from any organization" do
    delete admin_vendor_rate_url(@rival_rate), headers: auth_headers(@admin_session)
    assert_redirected_to admin_vendor_rates_path

    assert_not VendorRate.exists?(@rival_rate.id)
  end

  test "admin can create org-specific rate via organization_id param" do
    post admin_vendor_rates_url, params: {
      vendor_rate: {
        vendor_name: "org_specific",
        ai_model_name: "org_rate_test",
        input_rate_per_1k: 1.0,
        output_rate_per_1k: 1.0,
        unit_type: "tokens",
        active: true,
        organization_id: @rival.id
      }
    }, headers: auth_headers(@admin_session)

    created = VendorRate.find_by(ai_model_name: "org_rate_test")
    assert_not_nil created
    assert_equal @rival.id, created.organization_id,
      "Admin should be able to set organization_id for org-specific rates"
  end

  test "admin can create global rate without organization_id" do
    post admin_vendor_rates_url, params: {
      vendor_rate: {
        vendor_name: "global_test",
        ai_model_name: "global_rate_test",
        input_rate_per_1k: 1.0,
        output_rate_per_1k: 1.0,
        unit_type: "tokens",
        active: true
      }
    }, headers: auth_headers(@admin_session)

    created = VendorRate.find_by(ai_model_name: "global_rate_test")
    assert_not_nil created
    assert_nil created.organization_id, "Rate without organization_id should be global"
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
