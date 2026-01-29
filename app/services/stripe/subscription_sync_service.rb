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

      subscriptions.each do |subscription|
        customer_id = subscription.customer.is_a?(String) ? subscription.customer : subscription.customer.id
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
        price.unit_amount * (price.recurring.interval_count || 1).to_i.then { |count| price.unit_amount / count }
        price.unit_amount
      when "year"
        price.unit_amount / 12
      when "week"
        (price.unit_amount * 52) / 12
      when "day"
        (price.unit_amount * 365) / 12
      else
        0
      end
    end

    def update_customers(customer_revenues)
      synced_stripe_ids = Set.new

      customer_revenues.each do |stripe_customer_id, monthly_cents|
        customer = @organization.customers.find_or_initialize_by(
          stripe_customer_id: stripe_customer_id
        )

        if customer.new_record?
          stripe_customer = ::Stripe::Customer.retrieve(
            stripe_customer_id,
            { api_key: @organization.stripe_access_token }
          )
          customer.external_id = stripe_customer_id
          customer.name = stripe_customer.name || stripe_customer.email
        end

        customer.monthly_subscription_revenue_in_cents = monthly_cents
        customer.save!
        synced_stripe_ids.add(stripe_customer_id)
      end

      # Zero out revenue for customers whose subscriptions are no longer active
      @organization.customers
        .where.not(stripe_customer_id: [ nil, "" ])
        .where.not(stripe_customer_id: synced_stripe_ids.to_a)
        .update_all(monthly_subscription_revenue_in_cents: 0)
    end
  end
end
