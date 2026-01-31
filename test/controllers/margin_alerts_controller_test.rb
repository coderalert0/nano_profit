require "test_helper"

class MarginAlertsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_session = sessions(:admin_session)
    @regular_session = sessions(:regular_session)
    @alert = margin_alerts(:active_alert)
  end

  # --- Authentication ---

  test "unauthenticated user is redirected to login" do
    patch acknowledge_margin_alert_url(@alert)
    assert_redirected_to new_session_path
  end

  # --- Acknowledge ---

  test "org user can acknowledge with notes" do
    patch acknowledge_margin_alert_url(@alert),
      params: { notes: "Resolved by adjusting rates" },
      headers: auth_headers(@regular_session)

    assert_redirected_to alerts_path
    assert_equal "Alert acknowledged.", flash[:notice]

    @alert.reload
    assert_not_nil @alert.acknowledged_at
    assert_equal users(:regular_user), @alert.acknowledged_by
    assert_equal "Resolved by adjusting rates", @alert.notes
  end

  test "org user can acknowledge without notes" do
    patch acknowledge_margin_alert_url(@alert),
      headers: auth_headers(@regular_session)

    assert_redirected_to alerts_path
    @alert.reload
    assert_not_nil @alert.acknowledged_at
    assert_equal users(:regular_user), @alert.acknowledged_by
    assert_nil @alert.notes
  end

  test "admin can acknowledge alerts" do
    patch acknowledge_margin_alert_url(@alert),
      params: { notes: "Admin handled" },
      headers: auth_headers(@admin_session)

    assert_redirected_to alerts_path
    @alert.reload
    assert_not_nil @alert.acknowledged_at
    assert_equal users(:admin), @alert.acknowledged_by
  end

  # --- Acknowledge All ---

  test "org user can acknowledge all active alerts" do
    assert margin_alerts(:active_alert).acknowledged_at.nil?

    patch acknowledge_all_margin_alerts_url, headers: auth_headers(@regular_session)

    assert_redirected_to alerts_path
    assert_equal "All alerts acknowledged.", flash[:notice]
    assert_not_nil margin_alerts(:active_alert).reload.acknowledged_at
    assert_equal users(:regular_user), margin_alerts(:active_alert).acknowledged_by
  end

  # --- Turbo Stream ---

  test "turbo_stream response replaces alert row" do
    patch acknowledge_margin_alert_url(@alert),
      params: { notes: "All good" },
      headers: auth_headers(@regular_session).merge("Accept" => "text/vnd.turbo-stream.html"),
      as: :turbo_stream

    assert_response :success
    assert_includes response.body, "turbo-stream"
    @alert.reload
    assert_not_nil @alert.acknowledged_at
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
