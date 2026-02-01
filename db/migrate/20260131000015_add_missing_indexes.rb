class AddMissingIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :events, [:organization_id, :event_type], name: "idx_events_org_event_type"
    add_index :organizations, :stripe_user_id, unique: true,
      where: "stripe_user_id IS NOT NULL", name: "idx_organizations_stripe_user_id"
  end
end
