class AddUniqueIndexToCustomersStripeCustomerId < ActiveRecord::Migration[8.0]
  def change
    add_index :customers, [ :organization_id, :stripe_customer_id ],
      unique: true,
      where: "stripe_customer_id IS NOT NULL",
      name: "idx_customers_unique_org_stripe_id"
  end
end
