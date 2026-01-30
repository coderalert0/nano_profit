class RenameTelemetryToEvent < ActiveRecord::Migration[8.0]
  def change
    rename_table :usage_telemetry_events, :events
    rename_column :cost_entries, :usage_telemetry_event_id, :event_id
  end
end
