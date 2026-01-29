require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "requires external_id" do
    customer = Customer.new(organization: organizations(:acme), external_id: nil)
    assert_not customer.valid?
    assert_includes customer.errors[:external_id], "can't be blank"
  end

  test "external_id uniqueness enforced by DB constraint per organization" do
    existing = customers(:customer_one)
    dup = Customer.new(organization: existing.organization, external_id: existing.external_id)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
  end

  test "same external_id allowed in different organization" do
    other_org = Organization.create!(name: "Other Org")
    customer = Customer.new(organization: other_org, external_id: "cust_001", name: "Different Customer")
    assert customer.valid?
    assert_nothing_raised { customer.save! }
  end

  test "monthly_subscription_revenue_in_cents must be non-negative" do
    customer = customers(:customer_one)
    customer.monthly_subscription_revenue_in_cents = -1
    assert_not customer.valid?
    assert_includes customer.errors[:monthly_subscription_revenue_in_cents], "must be greater than or equal to 0"
  end

  test "monthly_subscription_revenue_in_cents allows zero" do
    customer = customers(:customer_one)
    customer.monthly_subscription_revenue_in_cents = 0
    assert customer.valid?
  end

  test "monthly_subscription_revenue_in_cents allows positive values" do
    customer = customers(:customer_one)
    customer.monthly_subscription_revenue_in_cents = 5000
    assert customer.valid?
  end

  test "monthly_subscription_revenue_in_cents defaults to zero" do
    customer = Customer.new(organization: organizations(:acme), external_id: "new_cust")
    assert_equal 0, customer.monthly_subscription_revenue_in_cents
  end
end
