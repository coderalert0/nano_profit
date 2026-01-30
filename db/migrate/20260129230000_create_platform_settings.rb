class CreatePlatformSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_settings do |t|
      t.string :key, null: false
      t.string :value, null: false
      t.timestamps
    end

    add_index :platform_settings, :key, unique: true
  end
end
