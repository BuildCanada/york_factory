class AddPublicationToMemos < ActiveRecord::Migration[8.1]
  def change
    add_column :memos, :publication, :string
    add_index  :memos, :publication
  end
end
