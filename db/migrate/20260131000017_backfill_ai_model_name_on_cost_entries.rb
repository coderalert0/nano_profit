class BackfillAiModelNameOnCostEntries < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    CostEntry.where(ai_model_name: nil).in_batches(of: 1000) do |batch|
      batch.update_all("ai_model_name = metadata->>'ai_model_name'")
    end
  end

  def down
    # No-op: column will be removed by rolling back previous migration
  end
end
