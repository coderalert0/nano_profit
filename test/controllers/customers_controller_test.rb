require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:regular_session)
    @customer = customers(:customer_one)
  end

  test "show renders margin by event type" do
    get customer_url(@customer), headers: auth_headers
    assert_response :success
    assert_select "h2", text: /Margin by Event Type/
    assert_select "a", text: "View all"
  end

  test "index renders customer list" do
    get customers_url, headers: auth_headers
    assert_response :success
    assert_select "[data-controller='infinite-scroll']"
  end

  test "index infinite scroll request returns rows partial" do
    get customers_url, params: { page: 1 },
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
