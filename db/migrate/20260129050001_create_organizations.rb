class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :api_key, null: false
      t.integer :margin_alert_threshold_bps, default: 0, null: false
      t.string :stripe_user_id
      t.string :stripe_access_token

      t.timestamps
    end

    add_index :organizations, :api_key, unique: true
  end
end
