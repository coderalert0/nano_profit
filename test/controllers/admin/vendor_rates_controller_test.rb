require "test_helper"

class Admin::VendorRatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_session = sessions(:admin_session)
    @regular_session = sessions(:regular_session)
    @rate = vendor_rates(:openai_gpt4_global)
  end

  # --- Authorization ---

  test "non-admin user is redirected from index" do
    get admin_vendor_rates_url, headers: auth_headers(@regular_session)
    assert_redirected_to root_path
    assert_equal "Not authorized.", flash[:alert]
  end

  test "unauthenticated user is redirected to login" do
    get admin_vendor_rates_url
    assert_redirected_to new_session_path
  end

  # --- Index ---

  test "admin can view index" do
    get admin_vendor_rates_url, headers: auth_headers(@admin_session)
    assert_response :success
    assert_select "table"
  end

  test "index filters by vendor" do
    get admin_vendor_rates_url, params: { vendor: "anthropic" }, headers: auth_headers(@admin_session)
    assert_response :success
    assert_select "td", text: "anthropic"
    assert_select "td", text: "openai", count: 0
  end

  test "index filters by model" do
    get admin_vendor_rates_url, params: { model: "claude-3" }, headers: auth_headers(@admin_session)
    assert_response :success
    assert_select "td", text: "claude-3"
  end

  test "index preserves filters with pagination" do
    get admin_vendor_rates_url, params: { vendor: "openai" }, headers: auth_headers(@admin_session)
    assert_response :success
    assert_select "td", text: "anthropic", count: 0
  end

  # --- Infinite Scroll ---

  test "infinite scroll request returns rows partial" do
    get admin_vendor_rates_url, params: { page: 1 },
      headers: auth_headers(@admin_session).merge("Turbo-Frame" => "infinite-scroll-rows")
    assert_response :success
    assert_select "h1", count: 0
  end

  # --- New / Create ---

  test "admin can view new form" do
    get new_admin_vendor_rate_url, headers: auth_headers(@admin_session)
    assert_response :success
    assert_select "form"
  end

  test "admin can create a vendor rate" do
    assert_difference "VendorRate.count", 1 do
      post admin_vendor_rates_url, params: {
        vendor_rate: {
          vendor_name: "google",
          ai_model_name: "gemini-pro",
          input_rate_per_1k: 0.0012,
          output_rate_per_1k: 0.0036,
          unit_type: "tokens",
          active: true
        }
      }, headers: auth_headers(@admin_session)
    end

    assert_redirected_to admin_vendor_rates_path
    assert_equal "Rate created successfully.", flash[:notice]
  end

  test "create with invalid params re-renders form" do
    assert_no_difference "VendorRate.count" do
      post admin_vendor_rates_url, params: {
        vendor_rate: { vendor_name: "", ai_model_name: "", input_rate_per_1k: nil, output_rate_per_1k: nil }
      }, headers: auth_headers(@admin_session)
    end

    assert_response :unprocessable_entity
  end

  # --- Edit / Update ---

  test "admin can view edit form" do
    get edit_admin_vendor_rate_url(@rate), headers: auth_headers(@admin_session)
    assert_response :success
    assert_select "form"
  end

  test "admin can update a vendor rate" do
    patch admin_vendor_rate_url(@rate), params: {
      vendor_rate: { input_rate_per_1k: 9.9999 }
    }, headers: auth_headers(@admin_session)

    assert_redirected_to admin_vendor_rates_path
    assert_equal "Rate updated successfully.", flash[:notice]
    assert_equal BigDecimal("9.9999"), @rate.reload.input_rate_per_1k
  end

  test "update with invalid params re-renders form" do
    patch admin_vendor_rate_url(@rate), params: {
      vendor_rate: { vendor_name: "" }
    }, headers: auth_headers(@admin_session)

    assert_response :unprocessable_entity
  end

  # --- Destroy ---

  test "admin can delete a vendor rate" do
    assert_difference "VendorRate.count", -1 do
      delete admin_vendor_rate_url(@rate), headers: auth_headers(@admin_session)
    end

    assert_redirected_to admin_vendor_rates_path
    assert_equal "Rate deleted.", flash[:notice]
  end

  # --- Non-admin blocked from mutations ---

  test "non-admin cannot create a vendor rate" do
    assert_no_difference "VendorRate.count" do
      post admin_vendor_rates_url, params: {
        vendor_rate: { vendor_name: "test", ai_model_name: "test", input_rate_per_1k: 1, output_rate_per_1k: 1 }
      }, headers: auth_headers(@regular_session)
    end

    assert_redirected_to root_path
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
