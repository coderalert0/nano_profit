require "test_helper"

class StripeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:admin_session)
    @org = organizations(:acme)
  end

  test "connect redirects to Stripe OAuth" do
    ENV["STRIPE_CLIENT_ID"] = "ca_test123"

    get stripe_connect_url, headers: auth_headers
    assert_response :redirect
    assert_includes response.location, "connect.stripe.com/oauth/authorize"
    assert_includes response.location, "ca_test123"
  ensure
    ENV.delete("STRIPE_CLIENT_ID")
  end

  test "disconnect revokes token and clears Stripe credentials" do
    @org.update!(stripe_user_id: "acct_test", stripe_access_token: "sk_test")

    # deauthorize raises Stripe::StripeError without valid keys; controller rescues it
    delete stripe_disconnect_url, headers: auth_headers
    assert_redirected_to settings_path

    @org.reload
    assert_nil @org.stripe_user_id
    assert_nil @org.stripe_access_token
  end

  test "sync redirects with error when not connected" do
    @org.update!(stripe_user_id: nil)

    post stripe_sync_url, headers: auth_headers
    assert_redirected_to settings_path
    assert_equal I18n.t("controllers.stripe.error"), flash[:alert]
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
