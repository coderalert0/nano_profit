require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "requires external_id" do
    customer = Customer.new(organization: organizations(:acme), external_id: nil)
    assert_not customer.valid?
    assert_includes customer.errors[:external_id], "can't be blank"
  end

  test "external_id must be unique per organization" do
    existing = customers(:customer_one)
    dup = Customer.new(organization: existing.organization, external_id: existing.external_id)
    assert_not dup.valid?
    assert_includes dup.errors[:external_id], "has already been taken"
  end

  test "same external_id allowed in different organization" do
    other_org = Organization.create!(name: "Other Org")
    customer = Customer.new(organization: other_org, external_id: "cust_001", name: "Different Customer")
    assert customer.valid?
  end
end
