class CreateStripeInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :stripe_invoices do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :customer, foreign_key: true
      t.string :stripe_invoice_id, null: false
      t.string :stripe_customer_id, null: false
      t.bigint :amount_in_cents, null: false
      t.string :currency, default: "usd"
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.datetime :paid_at, null: false
      t.string :hosted_invoice_url

      t.timestamps
    end

    add_index :stripe_invoices, :stripe_invoice_id, unique: true
    add_index :stripe_invoices, [ :organization_id, :customer_id, :period_start, :period_end ],
              name: "idx_stripe_invoices_org_cust_period"
    add_index :stripe_invoices, [ :organization_id, :period_start, :period_end ],
              name: "idx_stripe_invoices_org_period"
  end
end
