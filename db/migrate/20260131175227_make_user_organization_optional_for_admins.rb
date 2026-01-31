class MakeUserOrganizationOptionalForAdmins < ActiveRecord::Migration[8.0]
  def change
    change_column_null :users, :organization_id, true
    remove_foreign_key :users, :organizations
    add_foreign_key :users, :organizations, on_delete: :nullify
  end
end
