class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Covers the hot path: organization.events.processed.where(occurred_at: period)
    # Used by every MarginCalculator method, dashboard, customer pages, alert checks
    add_index :events, [:organization_id, :status, :occurred_at],
      name: "idx_events_org_status_occurred",
      algorithm: :concurrently

    # Covering index for CostEntry GROUP BY vendor_name + SUM(amount_in_cents)
    # Used by vendor_cost_breakdown, model_cost_breakdown, vendor filter dropdown
    add_index :cost_entries, [:event_id, :vendor_name, :amount_in_cents],
      name: "idx_cost_entries_event_vendor_amount",
      algorithm: :concurrently
  end
end
