class CreateCustomers < ActiveRecord::Migration[8.0]
  def change
    create_table :customers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :name
      t.bigint :monthly_subscription_revenue_in_cents, default: 0, null: false
      t.string :stripe_customer_id

      t.timestamps
    end

    add_index :customers, [ :organization_id, :external_id ], unique: true
  end
end
