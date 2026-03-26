class MoveSupportersToActionText < ActiveRecord::Migration[8.0]
  def change
    remove_column :memos, :supporters_en, :text
    remove_column :memos, :supporters_fr, :text
  end
end
