require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:regular_session)
  end

  test "show renders margin-by-dimension charts" do
    get dashboard_url, headers: auth_headers
    assert_response :success

    assert_select "h2", text: "Margin by Event Type (Bottom 10)"
    assert_select "h2", text: "Margin by Customer (Bottom 10)"
  end

  test "show does not render recent events table" do
    get dashboard_url, headers: auth_headers
    assert_response :success

    assert_select "#events-table-body", count: 0
    assert_select "#event-feed", count: 0
  end

  test "show with period param renders successfully" do
    get dashboard_url, params: { period: "30d" }, headers: auth_headers
    assert_response :success
  end

  private

  def auth_headers
    { "Cookie" => "session_id=#{sign_cookie(@session.id)}" }
  end

  def sign_cookie(value)
    cookies_jar = ActionDispatch::Request.new(Rails.application.env_config.merge("REQUEST_METHOD" => "GET")).cookie_jar
    cookies_jar.signed[:session_id] = value
    cookies_jar[:session_id]
  end
end
