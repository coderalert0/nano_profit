class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :customer, foreign_key: true
      t.string :unique_request_token, null: false
      t.string :customer_external_id, null: false
      t.string :customer_name
      t.string :event_type, null: false
      t.bigint :revenue_amount_in_cents, null: false
      t.decimal :total_cost_in_cents, precision: 15, scale: 6
      t.decimal :margin_in_cents, precision: 15, scale: 6
      t.jsonb :vendor_costs_raw, default: []
      t.jsonb :metadata, default: {}
      t.datetime :occurred_at
      t.string :status, default: "pending", null: false

      t.timestamps
    end

    add_index :events, :unique_request_token, unique: true
    add_index :events, [ :organization_id, :status ]
    add_index :events, [ :organization_id, :status, :occurred_at ],
              name: "idx_events_org_status_occurred"
    add_index :events, [ :customer_id, :occurred_at ]
  end
end
