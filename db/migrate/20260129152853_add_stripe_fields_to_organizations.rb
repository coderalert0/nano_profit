class AddStripeFieldsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :stripe_user_id, :string
    add_column :organizations, :stripe_access_token, :string
  end
end
