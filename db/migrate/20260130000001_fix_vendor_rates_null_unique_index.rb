class FixVendorRatesNullUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    remove_index :vendor_rates, name: "idx_vendor_rates_unique_vendor_model_org"

    add_index :vendor_rates, [:vendor_name, :ai_model_name, :organization_id],
      unique: true,
      where: "organization_id IS NOT NULL",
      name: "idx_vendor_rates_unique_vendor_model_org"

    add_index :vendor_rates, [:vendor_name, :ai_model_name],
      unique: true,
      where: "organization_id IS NULL",
      name: "idx_vendor_rates_unique_vendor_model_global"
  end
end
