module Stripe
  class SubscriptionSyncService
    def initialize(organization)
      @organization = organization
    end

    def sync
      return unless @organization.stripe_access_token.present?

      subscriptions = fetch_active_subscriptions
      customer_revenues = aggregate_by_customer(subscriptions)
      update_customers(customer_revenues)
    end

    private

    def fetch_active_subscriptions
      all_subscriptions = []
      starting_after = nil

      loop do
        params = { status: "active", limit: 100, expand: [ "data.customer" ] }
        params[:starting_after] = starting_after if starting_after

        response = ::Stripe::Subscription.list(
          params,
          { api_key: @organization.stripe_access_token }
        )

        all_subscriptions.concat(response.data)
        break unless response.has_more

        starting_after = response.data.last.id
      end

      all_subscriptions
    end

    def aggregate_by_customer(subscriptions)
      revenues = Hash.new(0)
      @stripe_customers = {}

      subscriptions.each do |subscription|
        customer_obj = subscription.customer
        customer_id = customer_obj.is_a?(String) ? customer_obj : customer_obj.id
        @stripe_customers[customer_id] = customer_obj unless customer_obj.is_a?(String)

        monthly_amount = subscription.items.data.sum do |item|
          calculate_monthly_amount(item.price)
        end
        revenues[customer_id] += monthly_amount
      end

      revenues
    end

    def calculate_monthly_amount(price)
      return 0 unless price.active

      case price.recurring&.interval
      when "month"
        count = [(price.recurring.interval_count || 1).to_i, 1].max
        price.unit_amount.to_d / count
      when "year"
        price.unit_amount.to_d / 12
      when "week"
        (price.unit_amount.to_d * 52) / 12
      when "day"
        (price.unit_amount.to_d * 365) / 12
      else
        0
      end
    end

    def update_customers(customer_revenues)
      synced_stripe_ids = Set.new

      ActiveRecord::Base.transaction do
        customer_revenues.each do |stripe_customer_id, monthly_cents|
          customer = find_or_create_customer(stripe_customer_id)
          customer.update!(monthly_subscription_revenue_in_cents: monthly_cents)
          synced_stripe_ids.add(stripe_customer_id)
        end

        # Zero out revenue for customers whose subscriptions are no longer active
        @organization.customers
          .where.not(stripe_customer_id: [nil, ""])
          .where.not(stripe_customer_id: synced_stripe_ids.to_a)
          .update_all(monthly_subscription_revenue_in_cents: 0)
      end
    end

    def find_or_create_customer(stripe_customer_id)
      # 1. Already linked by stripe_customer_id
      existing = @organization.customers.find_by(stripe_customer_id: stripe_customer_id)
      return existing if existing

      # 2. Try to link via metadata.external_id
      stripe_customer = @stripe_customers[stripe_customer_id]
      if stripe_customer.nil?
        stripe_customer = ::Stripe::Customer.retrieve(
          stripe_customer_id,
          { api_key: @organization.stripe_access_token }
        )
      end

      external_id = stripe_customer.respond_to?(:metadata) && stripe_customer.metadata&.respond_to?(:[]) ?
        stripe_customer.metadata["external_id"] : nil

      if external_id.present?
        by_external = @organization.customers.find_by(external_id: external_id)
        if by_external
          by_external.update!(stripe_customer_id: stripe_customer_id)
          return by_external
        end
      end

      # 3. Create new customer (handle race condition)
      @organization.customers.create_or_find_by!(external_id: stripe_customer_id) do |c|
        c.name = stripe_customer.name || stripe_customer.email
        c.stripe_customer_id = stripe_customer_id
      end
    end
  end
end
