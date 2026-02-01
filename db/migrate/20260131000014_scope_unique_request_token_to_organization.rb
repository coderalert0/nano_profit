class ScopeUniqueRequestTokenToOrganization < ActiveRecord::Migration[8.0]
  def change
    remove_index :events, :unique_request_token, unique: true
    add_index :events, [:organization_id, :unique_request_token],
      name: "idx_events_org_unique_request_token", unique: true
  end
end
