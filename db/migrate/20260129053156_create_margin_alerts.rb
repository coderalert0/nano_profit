class CreateMarginAlerts < ActiveRecord::Migration[8.0]
  def change
    create_table :margin_alerts do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :customer, foreign_key: true
      t.string :alert_type, null: false
      t.text :message, null: false
      t.datetime :acknowledged_at

      t.timestamps
    end

    add_index :margin_alerts, [ :organization_id, :acknowledged_at ]
  end
end
