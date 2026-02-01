class AddAiModelNameToCostEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :cost_entries, :ai_model_name, :string
    add_index :cost_entries, [:vendor_name, :ai_model_name], name: "idx_cost_entries_vendor_model"
  end
end
