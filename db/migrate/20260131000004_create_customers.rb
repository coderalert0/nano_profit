class CreateCustomers < ActiveRecord::Migration[8.0]
  def change
    create_table :customers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :name
      t.string :stripe_customer_id

      t.timestamps
    end

    add_index :customers, [ :organization_id, :external_id ], unique: true
    add_index :customers, [ :organization_id, :stripe_customer_id ],
              name: "idx_customers_unique_org_stripe_id", unique: true,
              where: "stripe_customer_id IS NOT NULL"
  end
end
