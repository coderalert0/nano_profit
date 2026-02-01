module Stripe
  class InvoiceSyncService
    def initialize(organization)
      @organization = organization
    end

    def sync
      return unless @organization.stripe_access_token.present?

      invoices = fetch_paid_invoices
      upsert_invoices(invoices)
    end

    def upsert_single_invoice(stripe_invoice)
      customer = find_or_create_customer(stripe_invoice)
      upsert_record(stripe_invoice, customer)
    end

    private

    def fetch_paid_invoices
      all_invoices = []
      starting_after = nil
      @stripe_customers = {}

      loop do
        params = { status: "paid", limit: 100, expand: [ "data.customer" ] }
        params[:starting_after] = starting_after if starting_after

        response = ::Stripe::Invoice.list(
          params,
          { api_key: @organization.stripe_access_token }
        )

        response.data.each do |invoice|
          all_invoices << invoice
          cache_stripe_customer(invoice)
        end

        break unless response.has_more

        starting_after = response.data.last.id
      end

      all_invoices
    rescue ::Stripe::StripeError => e
      Rails.logger.error("Stripe invoice fetch failed: #{e.message}")
      raise
    end

    def upsert_invoices(invoices)
      invoices.each do |invoice|
        customer = find_or_create_customer(invoice)
        upsert_record(invoice, customer)
      end
    end

    def upsert_record(invoice, customer)
      record = @organization.stripe_invoices.find_or_initialize_by(
        stripe_invoice_id: invoice.id
      )

      record.assign_attributes(
        customer: customer,
        stripe_customer_id: stripe_customer_id_from(invoice),
        amount_in_cents: invoice.amount_paid,
        currency: invoice.currency || "usd",
        period_start: Time.at(invoice.period_start).in_time_zone,
        period_end: Time.at(invoice.period_end).in_time_zone,
        paid_at: Time.at(invoice.status_transitions&.paid_at || invoice.created).in_time_zone,
        hosted_invoice_url: invoice.hosted_invoice_url
      )

      record.save!
      record
    rescue ActiveRecord::RecordNotUnique
      record = @organization.stripe_invoices.find_by!(stripe_invoice_id: invoice.id)
      record.update!(
        customer: customer,
        stripe_customer_id: stripe_customer_id_from(invoice),
        amount_in_cents: invoice.amount_paid,
        currency: invoice.currency || "usd",
        period_start: Time.at(invoice.period_start).in_time_zone,
        period_end: Time.at(invoice.period_end).in_time_zone,
        paid_at: Time.at(invoice.status_transitions&.paid_at || invoice.created).in_time_zone,
        hosted_invoice_url: invoice.hosted_invoice_url
      )
      record
    end

    def find_or_create_customer(invoice)
      stripe_cust_id = stripe_customer_id_from(invoice)

      # 1. Already linked by stripe_customer_id
      existing = @organization.customers.find_by(stripe_customer_id: stripe_cust_id)
      return existing if existing

      # 2. Try to link via metadata.external_id
      stripe_customer = resolve_stripe_customer(invoice)
      external_id = if stripe_customer && stripe_customer.respond_to?(:metadata) && stripe_customer.metadata&.respond_to?(:[])
        stripe_customer.metadata["external_id"]
      end

      if external_id.present?
        by_external = @organization.customers.find_by(external_id: external_id)
        if by_external
          by_external.update!(stripe_customer_id: stripe_cust_id)
          return by_external
        end
      end

      # 3. Create new customer (handle race condition)
      @organization.customers.create_or_find_by!(external_id: stripe_cust_id) do |c|
        c.name = stripe_customer&.name || stripe_customer&.email || stripe_cust_id
        c.stripe_customer_id = stripe_cust_id
      end
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors[:external_id]&.any?
      @organization.customers.find_by!(external_id: stripe_cust_id)
    end

    def stripe_customer_id_from(invoice)
      customer_obj = invoice.customer
      customer_obj.is_a?(String) ? customer_obj : customer_obj.id
    end

    def resolve_stripe_customer(invoice)
      customer_obj = invoice.customer
      stripe_cust_id = stripe_customer_id_from(invoice)

      return customer_obj unless customer_obj.is_a?(String)

      @stripe_customers ||= {}
      @stripe_customers[stripe_cust_id] ||= ::Stripe::Customer.retrieve(
        stripe_cust_id,
        { api_key: @organization.stripe_access_token }
      )
    end

    def cache_stripe_customer(invoice)
      customer_obj = invoice.customer
      return if customer_obj.is_a?(String)

      @stripe_customers ||= {}
      @stripe_customers[customer_obj.id] = customer_obj
    end
  end
end
