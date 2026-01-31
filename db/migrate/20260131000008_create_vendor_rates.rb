class CreateVendorRates < ActiveRecord::Migration[8.0]
  def change
    create_table :vendor_rates do |t|
      t.string :vendor_name, null: false
      t.string :ai_model_name, null: false
      t.decimal :input_rate_per_1k, precision: 15, scale: 6, null: false
      t.decimal :output_rate_per_1k, precision: 15, scale: 6, null: false
      t.string :unit_type, default: "tokens", null: false
      t.boolean :active, default: true, null: false
      t.references :organization, foreign_key: true

      t.timestamps
    end

    add_index :vendor_rates, [ :vendor_name, :ai_model_name, :organization_id ],
              name: "idx_vendor_rates_unique_vendor_model_org", unique: true,
              where: "organization_id IS NOT NULL"
    add_index :vendor_rates, [ :vendor_name, :ai_model_name ],
              name: "idx_vendor_rates_unique_vendor_model_global", unique: true,
              where: "organization_id IS NULL"
  end
end
