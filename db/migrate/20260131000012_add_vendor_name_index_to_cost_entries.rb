class AddVendorNameIndexToCostEntries < ActiveRecord::Migration[8.0]
  def change
    add_index :cost_entries, :vendor_name, name: "idx_cost_entries_vendor_name"
  end
end
