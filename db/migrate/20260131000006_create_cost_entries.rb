class CreateCostEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :cost_entries do |t|
      t.references :event, null: false, foreign_key: true
      t.string :vendor_name
      t.decimal :amount_in_cents, precision: 15, scale: 6
      t.decimal :unit_count
      t.string :unit_type
      t.jsonb :metadata

      t.timestamps
    end

    add_index :cost_entries, [ :event_id, :vendor_name, :amount_in_cents ],
              name: "idx_cost_entries_event_vendor_amount"
  end
end
