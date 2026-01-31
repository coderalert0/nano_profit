class ConvertMarginAlertsToAggregate < ActiveRecord::Migration[8.0]
  def change
    # New dimension columns
    add_column :margin_alerts, :dimension, :string, null: false, default: "customer"
    add_column :margin_alerts, :dimension_value, :string

    # New org setting for rolling period
    add_column :organizations, :margin_alert_period_days, :integer, null: false, default: 7

    # Remove old unique index
    remove_index :margin_alerts, name: "idx_margin_alerts_unique_unacknowledged"

    # New unique index: one unacknowledged alert per org/dimension/value/type
    add_index :margin_alerts, [:organization_id, :dimension, :dimension_value, :alert_type],
              unique: true,
              where: "(acknowledged_at IS NULL)",
              name: "idx_margin_alerts_unique_unacked_dimension"

    # Remove customer_id FK (dimension_value stores customer_id or event_type string)
    remove_foreign_key :margin_alerts, :customers
    remove_column :margin_alerts, :customer_id
  end
end
