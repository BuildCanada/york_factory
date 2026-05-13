class MakeBuildCanadaAnExplicitMemoPublication < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE memos SET publication = 'build_canada' WHERE publication IS NULL;
    SQL

    execute <<~SQL
      UPDATE friendly_id_slugs
      SET scope = memos.publication
      FROM memos
      WHERE friendly_id_slugs.sluggable_type = 'Memo'
        AND friendly_id_slugs.sluggable_id = memos.id
        AND friendly_id_slugs.scope IS DISTINCT FROM memos.publication;
    SQL

    change_column_default :memos, :publication, "build_canada"
    change_column_null    :memos, :publication, false

    remove_index :memos, :slug
    add_index    :memos, [:slug, :publication], unique: true
  end

  def down
    remove_index :memos, [:slug, :publication]
    add_index    :memos, :slug, unique: true

    change_column_null    :memos, :publication, true
    change_column_default :memos, :publication, nil

    execute <<~SQL
      UPDATE friendly_id_slugs SET scope = NULL
      WHERE sluggable_type = 'Memo';
    SQL

    execute <<~SQL
      UPDATE memos SET publication = NULL WHERE publication = 'build_canada';
    SQL
  end
end
