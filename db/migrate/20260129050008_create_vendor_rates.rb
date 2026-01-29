class CreateVendorRates < ActiveRecord::Migration[8.0]
  def change
    create_table :vendor_rates do |t|
      t.string :vendor_name, null: false
      t.string :ai_model_name, null: false
      t.decimal :input_rate_per_1k, precision: 10, scale: 4, null: false
      t.decimal :output_rate_per_1k, precision: 10, scale: 4, null: false
      t.string :unit_type, default: "tokens", null: false
      t.boolean :active, default: true, null: false
      t.references :organization, foreign_key: true

      t.timestamps
    end

    add_index :vendor_rates, [ :vendor_name, :ai_model_name, :organization_id ], unique: true, name: "idx_vendor_rates_unique_vendor_model_org"
  end
end
