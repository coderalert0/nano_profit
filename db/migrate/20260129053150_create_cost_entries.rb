class CreateCostEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :cost_entries do |t|
      t.references :usage_telemetry_event, null: false, foreign_key: true
      t.string :vendor_name
      t.bigint :amount_in_cents
      t.decimal :unit_count
      t.string :unit_type
      t.jsonb :metadata

      t.timestamps
    end
  end
end
