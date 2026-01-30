require "test_helper"
require "ostruct"

class Stripe::SubscriptionSyncServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:acme)
    @org.update!(stripe_user_id: "acct_test123", stripe_access_token: "sk_test_token")
  end

  test "sync creates new customers from Stripe subscriptions" do
    mock_subscription = build_mock_subscription(
      id: "sub_new",
      customer_id: "cus_new_customer",
      customer_name: "New Stripe Customer",
      amount: 9900,
      interval: "month"
    )

    mock_list = ::OpenStruct.new(data: [ mock_subscription ], has_more: false)
    mock_stripe_customer = ::OpenStruct.new(
      id: "cus_new_customer",
      name: "New Stripe Customer",
      email: "new@example.com",
      metadata: { "external_id" => nil }
    )

    service = Stripe::SubscriptionSyncService.new(@org)
    service.define_singleton_method(:fetch_active_subscriptions) { [ mock_subscription ] }

    original_retrieve = ::Stripe::Customer.method(:retrieve)
    ::Stripe::Customer.define_singleton_method(:retrieve) { |*_args| mock_stripe_customer }

    assert_difference "Customer.count", 1 do
      service.sync
    end

    customer = @org.customers.find_by(stripe_customer_id: "cus_new_customer")
    assert_not_nil customer
    assert_equal 9900, customer.monthly_subscription_revenue_in_cents
    assert_equal "New Stripe Customer", customer.name
  ensure
    ::Stripe::Customer.define_singleton_method(:retrieve, original_retrieve) if original_retrieve
  end

  test "sync updates existing customer subscription revenue" do
    customer = customers(:customer_one)
    customer.update!(stripe_customer_id: "cus_existing")

    mock_subscription = build_mock_subscription(
      id: "sub_existing",
      customer_id: "cus_existing",
      amount: 4900,
      interval: "month"
    )

    service = Stripe::SubscriptionSyncService.new(@org)
    service.define_singleton_method(:fetch_active_subscriptions) { [ mock_subscription ] }
    service.sync

    customer.reload
    assert_equal 4900, customer.monthly_subscription_revenue_in_cents
  end

  test "sync converts yearly prices to monthly" do
    customer = customers(:customer_one)
    customer.update!(stripe_customer_id: "cus_yearly")

    mock_subscription = build_mock_subscription(
      id: "sub_yearly",
      customer_id: "cus_yearly",
      amount: 12000,
      interval: "year"
    )

    service = Stripe::SubscriptionSyncService.new(@org)
    service.define_singleton_method(:fetch_active_subscriptions) { [ mock_subscription ] }
    service.sync

    customer.reload
    assert_equal 1000, customer.monthly_subscription_revenue_in_cents
  end

  test "sync zeros out revenue for customers no longer subscribed" do
    customer = customers(:customer_with_subscription)
    customer.update!(stripe_customer_id: "cus_cancelled")

    assert_equal 5000, customer.monthly_subscription_revenue_in_cents

    service = Stripe::SubscriptionSyncService.new(@org)
    service.define_singleton_method(:fetch_active_subscriptions) { [] }
    service.sync

    customer.reload
    assert_equal 0, customer.monthly_subscription_revenue_in_cents
  end

  test "sync handles multi-month interval correctly" do
    customer = customers(:customer_one)
    customer.update!(stripe_customer_id: "cus_quarterly")

    mock_subscription = build_mock_subscription(
      id: "sub_quarterly",
      customer_id: "cus_quarterly",
      amount: 9000,
      interval: "month",
      interval_count: 3
    )

    service = Stripe::SubscriptionSyncService.new(@org)
    service.define_singleton_method(:fetch_active_subscriptions) { [ mock_subscription ] }
    service.sync

    customer.reload
    assert_equal 3000, customer.monthly_subscription_revenue_in_cents
  end

  test "sync does nothing without stripe_access_token" do
    @org.update!(stripe_access_token: nil)

    assert_nothing_raised do
      Stripe::SubscriptionSyncService.new(@org).sync
    end
  end

  test "sync links Stripe subscription to existing telemetry customer via metadata.external_id" do
    # Create a customer via telemetry (has external_id but no stripe_customer_id)
    telemetry_customer = @org.customers.create!(
      external_id: "tel_cust_100",
      name: "Telemetry Customer"
    )

    mock_subscription = build_mock_subscription(
      id: "sub_link",
      customer_id: "cus_stripe_link",
      customer_name: "Telemetry Customer",
      amount: 7500,
      interval: "month",
      metadata: { "external_id" => "tel_cust_100" }
    )

    service = Stripe::SubscriptionSyncService.new(@org)
    service.define_singleton_method(:fetch_active_subscriptions) { [ mock_subscription ] }

    assert_no_difference "Customer.count" do
      service.sync
    end

    telemetry_customer.reload
    assert_equal "cus_stripe_link", telemetry_customer.stripe_customer_id
    assert_equal 7500, telemetry_customer.monthly_subscription_revenue_in_cents
  end

  private

  def build_mock_subscription(id:, customer_id:, amount:, interval:, interval_count: 1, customer_name: nil, metadata: {})
    price = ::OpenStruct.new(
      unit_amount: amount,
      active: true,
      recurring: ::OpenStruct.new(interval: interval, interval_count: interval_count)
    )

    item = ::OpenStruct.new(price: price)

    ::OpenStruct.new(
      id: id,
      customer: ::OpenStruct.new(id: customer_id, name: customer_name, metadata: metadata),
      items: ::OpenStruct.new(data: [ item ])
    )
  end
end
