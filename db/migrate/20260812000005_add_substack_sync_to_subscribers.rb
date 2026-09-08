class AddSubstackSyncToSubscribers < ActiveRecord::Migration[8.1]
  def change
    add_column :subscribers, :substack_synced_at, :datetime
    add_column :subscribers, :substack_import_id, :bigint
    add_index :subscribers, [ :substack_synced_at, :id ]
  end
end
