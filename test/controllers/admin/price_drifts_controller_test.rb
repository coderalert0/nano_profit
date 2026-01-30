require "test_helper"

class Admin::PriceDriftsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_session = sessions(:admin_session)
    @regular_session = sessions(:regular_session)
    @pending_drift = price_drifts(:pending_drift)
  end

  # --- Authorization ---

  test "non-admin user is redirected from index" do
    get admin_price_drifts_url, headers: auth_headers(@regular_session)
    assert_redirected_to root_path
    assert_equal "Not authorized.", flash[:alert]
  end

  test "unauthenticated user is redirected to login" do
    get admin_price_drifts_url
    assert_redirected_to new_session_path
  end

  # --- Index ---

  test "admin can view index" do
    get admin_price_drifts_url, headers: auth_headers(@admin_session)
    assert_response :success
    assert_select "table"
  end

  # --- Apply ---

  test "admin can apply a pending drift" do
    rate = vendor_rates(:openai_gpt4_global)
    original_input = rate.input_rate_per_1k

    patch apply_admin_price_drift_url(@pending_drift), headers: auth_headers(@admin_session)

    assert_redirected_to admin_price_drifts_path
    assert_equal "Price drift applied — vendor rate updated.", flash[:notice]

    @pending_drift.reload
    rate.reload

    assert_equal "applied", @pending_drift.status
    assert_equal @pending_drift.new_input_rate, rate.input_rate_per_1k
    assert_equal @pending_drift.new_output_rate, rate.output_rate_per_1k
  end

  # --- Update Threshold ---

  test "admin can update drift threshold" do
    patch update_threshold_admin_price_drifts_url, params: { drift_threshold: "0.005" }, headers: auth_headers(@admin_session)

    assert_redirected_to admin_price_drifts_path
    assert_match "Drift threshold updated", flash[:notice]
    assert_equal "0.005".to_d, PlatformSetting.drift_threshold
  end

  test "admin cannot set negative threshold" do
    patch update_threshold_admin_price_drifts_url, params: { drift_threshold: "-1" }, headers: auth_headers(@admin_session)

    assert_redirected_to admin_price_drifts_path
    assert_equal "Threshold must be zero or positive.", flash[:alert]
  end

  test "non-admin cannot update threshold" do
    patch update_threshold_admin_price_drifts_url, params: { drift_threshold: "0.005" }, headers: auth_headers(@regular_session)
    assert_redirected_to root_path
  end

  test "index displays current threshold" do
    PlatformSetting.drift_threshold = "0.05"
    get admin_price_drifts_url, headers: auth_headers(@admin_session)
    assert_response :success
    assert_select "input[name='drift_threshold'][value='0.05']"
  end

  # --- Ignore ---

  test "admin can ignore a pending drift" do
    patch ignore_admin_price_drift_url(@pending_drift), headers: auth_headers(@admin_session)

    assert_redirected_to admin_price_drifts_path
    assert_equal "Price drift ignored.", flash[:notice]

    assert_equal "ignored", @pending_drift.reload.status
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
