require "test_helper"
require "ostruct"

class Stripe::InvoiceSyncServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:acme)
    @org.update!(stripe_user_id: "acct_test123", stripe_access_token: "sk_test_token")
  end

  test "sync creates stripe_invoice records from paid invoices" do
    mock_invoice = build_mock_invoice(
      id: "inv_new_001",
      customer_id: "cus_new_customer",
      customer_name: "New Stripe Customer",
      amount_paid: 9900,
      period_start: Time.new(2026, 1, 1).to_i,
      period_end: Time.new(2026, 2, 1).to_i
    )

    mock_list = ::OpenStruct.new(data: [ mock_invoice ], has_more: false)
    mock_stripe_customer = ::OpenStruct.new(
      id: "cus_new_customer",
      name: "New Stripe Customer",
      email: "new@example.com",
      metadata: { "external_id" => nil }
    )

    service = Stripe::InvoiceSyncService.new(@org)
    service.define_singleton_method(:fetch_paid_invoices) { [ mock_invoice ] }

    original_retrieve = ::Stripe::Customer.method(:retrieve)
    ::Stripe::Customer.define_singleton_method(:retrieve) { |*_args| mock_stripe_customer }

    assert_difference "StripeInvoice.count", 1 do
      assert_difference "Customer.count", 1 do
        service.sync
      end
    end

    invoice_record = @org.stripe_invoices.find_by(stripe_invoice_id: "inv_new_001")
    assert_not_nil invoice_record
    assert_equal 9900, invoice_record.amount_in_cents
    assert_equal "cus_new_customer", invoice_record.stripe_customer_id
    assert_not_nil invoice_record.customer
    assert_equal "New Stripe Customer", invoice_record.customer.name
  ensure
    ::Stripe::Customer.define_singleton_method(:retrieve, original_retrieve) if original_retrieve
  end

  test "sync links invoice to existing customer by stripe_customer_id" do
    customer = customers(:customer_one)
    customer.update!(stripe_customer_id: "cus_existing")

    mock_invoice = build_mock_invoice(
      id: "inv_existing_001",
      customer_id: "cus_existing",
      amount_paid: 4900,
      period_start: Time.new(2026, 1, 1).to_i,
      period_end: Time.new(2026, 2, 1).to_i
    )

    service = Stripe::InvoiceSyncService.new(@org)
    service.define_singleton_method(:fetch_paid_invoices) { [ mock_invoice ] }

    assert_no_difference "Customer.count" do
      service.sync
    end

    invoice_record = @org.stripe_invoices.find_by(stripe_invoice_id: "inv_existing_001")
    assert_equal customer.id, invoice_record.customer_id
  end

  test "sync links invoice to existing customer via metadata.external_id" do
    event_customer = @org.customers.create!(
      external_id: "tel_cust_100",
      name: "Telemetry Customer"
    )

    mock_invoice = build_mock_invoice(
      id: "inv_link_001",
      customer_id: "cus_stripe_link",
      customer_name: "Telemetry Customer",
      amount_paid: 7500,
      period_start: Time.new(2026, 1, 1).to_i,
      period_end: Time.new(2026, 2, 1).to_i,
      metadata: { "external_id" => "tel_cust_100" }
    )

    service = Stripe::InvoiceSyncService.new(@org)
    service.define_singleton_method(:fetch_paid_invoices) { [ mock_invoice ] }

    assert_no_difference "Customer.count" do
      service.sync
    end

    event_customer.reload
    assert_equal "cus_stripe_link", event_customer.stripe_customer_id

    invoice_record = @org.stripe_invoices.find_by(stripe_invoice_id: "inv_link_001")
    assert_equal event_customer.id, invoice_record.customer_id
  end

  test "sync is idempotent - same invoice twice creates 1 record" do
    mock_invoice = build_mock_invoice(
      id: "inv_idempotent_001",
      customer_id: "cus_idem",
      customer_name: "Idempotent Customer",
      amount_paid: 3000,
      period_start: Time.new(2026, 1, 1).to_i,
      period_end: Time.new(2026, 2, 1).to_i
    )

    mock_stripe_customer = ::OpenStruct.new(
      id: "cus_idem",
      name: "Idempotent Customer",
      email: "idem@example.com",
      metadata: { "external_id" => nil }
    )

    original_retrieve = ::Stripe::Customer.method(:retrieve)
    ::Stripe::Customer.define_singleton_method(:retrieve) { |*_args| mock_stripe_customer }

    service = Stripe::InvoiceSyncService.new(@org)

    # First sync
    service.define_singleton_method(:fetch_paid_invoices) { [ mock_invoice ] }
    service.sync

    # Second sync with same invoice
    service2 = Stripe::InvoiceSyncService.new(@org)
    service2.define_singleton_method(:fetch_paid_invoices) { [ mock_invoice ] }

    assert_no_difference "StripeInvoice.count" do
      service2.sync
    end
  ensure
    ::Stripe::Customer.define_singleton_method(:retrieve, original_retrieve) if original_retrieve
  end

  test "sync does nothing without stripe_access_token" do
    @org.update!(stripe_access_token: nil)

    assert_nothing_raised do
      Stripe::InvoiceSyncService.new(@org).sync
    end
  end

  test "upsert_single_invoice creates a single invoice record" do
    customer = customers(:customer_one)
    customer.update!(stripe_customer_id: "cus_single")

    mock_invoice = build_mock_invoice(
      id: "inv_single_001",
      customer_id: "cus_single",
      amount_paid: 2500,
      period_start: Time.new(2026, 1, 1).to_i,
      period_end: Time.new(2026, 2, 1).to_i
    )

    service = Stripe::InvoiceSyncService.new(@org)

    assert_difference "StripeInvoice.count", 1 do
      service.upsert_single_invoice(mock_invoice)
    end

    record = @org.stripe_invoices.find_by(stripe_invoice_id: "inv_single_001")
    assert_equal 2500, record.amount_in_cents
    assert_equal customer.id, record.customer_id
  end

  private

  def build_mock_invoice(id:, customer_id:, amount_paid: 1000, period_start:, period_end:, customer_name: nil, metadata: {})
    customer_obj = ::OpenStruct.new(
      id: customer_id,
      name: customer_name,
      email: "#{customer_id}@example.com",
      metadata: metadata
    )

    ::OpenStruct.new(
      id: id,
      customer: customer_obj,
      amount_paid: amount_paid,
      currency: "usd",
      period_start: period_start,
      period_end: period_end,
      status_transitions: ::OpenStruct.new(paid_at: period_start),
      hosted_invoice_url: "https://invoice.stripe.com/#{id}",
      created: period_start
    )
  end
end
