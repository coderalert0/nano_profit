class CreateMarginAlerts < ActiveRecord::Migration[8.0]
  def change
    create_table :margin_alerts do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :alert_type, null: false
      t.text :message, null: false
      t.datetime :acknowledged_at
      t.text :notes
      t.bigint :acknowledged_by_id
      t.string :dimension, default: "customer", null: false
      t.string :dimension_value

      t.timestamps
    end

    add_foreign_key :margin_alerts, :users, column: :acknowledged_by_id
    add_index :margin_alerts, :acknowledged_by_id
    add_index :margin_alerts, [ :organization_id, :acknowledged_at ]
    add_index :margin_alerts,
              [ :organization_id, :dimension, :dimension_value, :alert_type ],
              name: "idx_margin_alerts_unique_unacked_dimension", unique: true,
              where: "acknowledged_at IS NULL"
  end
end
