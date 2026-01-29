class CreateCustomers < ActiveRecord::Migration[8.0]
  def change
    create_table :customers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :name

      t.timestamps
    end

    add_index :customers, [ :organization_id, :external_id ], unique: true
  end
end
