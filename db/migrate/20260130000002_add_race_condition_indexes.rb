class AddRaceConditionIndexes < ActiveRecord::Migration[8.0]
  def up
    # Remove duplicate unacknowledged margin alerts before adding unique index
    execute <<~SQL
      DELETE FROM margin_alerts
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM margin_alerts
        WHERE acknowledged_at IS NULL
        GROUP BY organization_id, customer_id, alert_type
      )
      AND acknowledged_at IS NULL
    SQL

    add_index :margin_alerts,
      [:organization_id, :customer_id, :alert_type],
      unique: true,
      where: "acknowledged_at IS NULL",
      name: "idx_margin_alerts_unique_unacknowledged"

    # Remove duplicate pending price drifts before adding unique index
    execute <<~SQL
      DELETE FROM price_drifts
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM price_drifts
        WHERE status = 0
        GROUP BY vendor_name, ai_model_name
      )
      AND status = 0
    SQL

    add_index :price_drifts,
      [:vendor_name, :ai_model_name],
      unique: true,
      where: "status = 0",
      name: "idx_price_drifts_unique_pending"
  end

  def down
    remove_index :margin_alerts, name: "idx_margin_alerts_unique_unacknowledged"
    remove_index :price_drifts, name: "idx_price_drifts_unique_pending"
  end
end
