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

  test "has_many stripe_invoices" do
    customer = customers(:customer_with_subscription)
    assert customer.stripe_invoices.count > 0
  end

  test "destroying customer destroys its stripe_invoices" do
    customer = customers(:customer_with_subscription)
    invoice_ids = customer.stripe_invoice_ids

    customer.destroy!
    assert_equal 0, StripeInvoice.where(id: invoice_ids).count
  end
end
