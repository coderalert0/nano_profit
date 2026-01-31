require "test_helper"

class EventTypesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:regular_session)
  end

  test "index renders event type list" do
    get event_types_url, headers: auth_headers
    assert_response :success
    assert_select "table"
    assert_select "[data-controller='infinite-scroll']"
  end

  test "index with period filter" do
    get event_types_url, params: { period: "30d" }, headers: auth_headers
    assert_response :success
  end

  test "index infinite scroll returns rows partial" do
    get event_types_url, params: { page: 1 },
      headers: auth_headers.merge("Turbo-Frame" => "infinite-scroll-rows")
    assert_response :success
    assert_select "h1", count: 0
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
