class AddMonthlySubscriptionRevenueToCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :customers, :monthly_subscription_revenue_in_cents, :bigint, default: 0, null: false
  end
end
