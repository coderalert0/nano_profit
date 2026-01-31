class CreatePriceDrifts < ActiveRecord::Migration[8.0]
  def change
    create_table :price_drifts do |t|
      t.string :vendor_name, null: false
      t.string :ai_model_name, null: false
      t.decimal :old_input_rate, precision: 15, scale: 6, null: false
      t.decimal :new_input_rate, precision: 15, scale: 6, null: false
      t.decimal :old_output_rate, precision: 15, scale: 6, null: false
      t.decimal :new_output_rate, precision: 15, scale: 6, null: false
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :price_drifts, [ :vendor_name, :ai_model_name ],
              name: "idx_price_drifts_unique_pending", unique: true,
              where: "status = 0"
  end
end
