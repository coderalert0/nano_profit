class AddAcknowledgementFieldsToMarginAlerts < ActiveRecord::Migration[8.0]
  def change
    add_column :margin_alerts, :notes, :text
    add_reference :margin_alerts, :acknowledged_by, null: true, foreign_key: { to_table: :users }
  end
end
