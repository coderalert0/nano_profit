class ChangeCostColumnsToDecimal < ActiveRecord::Migration[8.0]
  def up
    change_column :cost_entries, :amount_in_cents, :decimal, precision: 15, scale: 6
    change_column :usage_telemetry_events, :total_cost_in_cents, :decimal, precision: 15, scale: 6
    change_column :usage_telemetry_events, :margin_in_cents, :decimal, precision: 15, scale: 6
  end

  def down
    change_column :cost_entries, :amount_in_cents, :bigint
    change_column :usage_telemetry_events, :total_cost_in_cents, :bigint
    change_column :usage_telemetry_events, :margin_in_cents, :bigint
  end
end
