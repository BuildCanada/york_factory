class AddPledgedToVoteAt < ActiveRecord::Migration[8.1]
  def up
    # When the subscriber last pledged to vote (election tracker). Stamped by
    # Warehouse::PledgeToVote on every pledge and synced to the HubSpot
    # contact property of the same name.
    add_column :subscribers, :pledged_to_vote_at, :datetime
    add_column :hubspot_contacts, :pledged_to_vote_at, :datetime

    # Carry existing pledgers over from their most recent pledge.
    execute <<~SQL
      UPDATE subscribers
      SET pledged_to_vote_at = pledges.latest_pledged_at
      FROM (
        SELECT subscriber_id, MAX(pledged_at) AS latest_pledged_at
        FROM warehouse.pledges_to_vote
        GROUP BY subscriber_id
      ) pledges
      WHERE subscribers.id = pledges.subscriber_id
    SQL
  end

  def down
    remove_column :subscribers, :pledged_to_vote_at
    remove_column :hubspot_contacts, :pledged_to_vote_at
  end
end
