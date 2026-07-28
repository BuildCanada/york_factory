class AddPublishedAtToWarehouseElections < ActiveRecord::Migration[8.1]
  # Elections are now built up in admin before they go live — a region whose
  # candidate list has to be entered by hand (Ottawa) shouldn't appear on the
  # public API with no races in it. Follows the same published_at convention as
  # posts and memos (see Publishable), so a null value is a draft and a future
  # value is scheduled.
  def up
    add_column "warehouse.elections", :published_at, :datetime, precision: 6

    # Every election that already exists was public before this column did;
    # leaving them null would drop them from the API on deploy.
    execute <<~SQL
      UPDATE warehouse.elections SET published_at = created_at WHERE published_at IS NULL
    SQL
  end

  def down
    remove_column "warehouse.elections", :published_at
  end
end
