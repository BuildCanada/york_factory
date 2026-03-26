class MoveBuilderAuthorToActionText < ActiveRecord::Migration[8.0]
  def change
    remove_column :builders, :author_en, :text
    remove_column :builders, :author_fr, :text
  end
end
