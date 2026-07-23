class AddShareTokenToPledgesToVote < ActiveRecord::Migration[8.1]
  # Public identifier for a pledge's shareable page on the election tracker.
  # Random rather than the sequential id so pledge URLs can't be enumerated.
  def up
    add_column "warehouse.pledges_to_vote", :share_token, :string

    # Backfill existing pledges (md5 hex keeps it lowercase alphanumeric,
    # matching the format the model generates)
    execute <<~SQL
      UPDATE warehouse.pledges_to_vote
      SET share_token = lower(substr(md5(random()::text || id::text), 1, 10))
      WHERE share_token IS NULL
    SQL

    change_column_null "warehouse.pledges_to_vote", :share_token, false
    add_index "warehouse.pledges_to_vote", :share_token,
      unique: true, name: "ux_pledges_to_vote_share_token"
  end

  def down
    remove_column "warehouse.pledges_to_vote", :share_token
  end
end
