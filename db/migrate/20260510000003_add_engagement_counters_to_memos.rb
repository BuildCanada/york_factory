class AddEngagementCountersToMemos < ActiveRecord::Migration[8.1]
  def up
    add_column :memos, :endorsements_count,       :integer, null: false, default: 0
    add_column :memos, :approved_critiques_count, :integer, null: false, default: 0

    Memo.reset_column_information
    Memo.find_each do |memo|
      Memo.reset_counters(memo.id, :endorsements)
      approved = Critique.where(memo_id: memo.id, status: Critique.statuses[:approved]).count
      Memo.where(id: memo.id).update_all(approved_critiques_count: approved)
    end
  end

  def down
    remove_column :memos, :endorsements_count
    remove_column :memos, :approved_critiques_count
  end
end
