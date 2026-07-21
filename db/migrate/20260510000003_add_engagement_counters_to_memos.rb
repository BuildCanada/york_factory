class AddEngagementCountersToMemos < ActiveRecord::Migration[8.1]
  def change
    add_column :memos, :endorsements_count,       :integer, null: false, default: 0
    add_column :memos, :approved_critiques_count, :integer, null: false, default: 0
  end
end
