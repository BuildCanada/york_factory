class CreateWarehousePledgesToVote < ActiveRecord::Migration[8.1]
  # "I pledge to vote" submissions from the election tracker, one per
  # subscriber per election: who pledged (subscriber upserted by email, same
  # low-friction pattern as the newsletter signup), which election, which
  # region of it (e.g. a Toronto ward, or the jurisdiction slug for a
  # city-wide pledge), and when.
  def up
    execute <<~SQL
      CREATE TABLE warehouse.pledges_to_vote (
        id bigserial PRIMARY KEY,
        election_id bigint NOT NULL REFERENCES warehouse.elections(id) ON DELETE CASCADE,
        subscriber_id bigint NOT NULL REFERENCES public.subscribers(id) ON DELETE CASCADE,
        region varchar NOT NULL,
        pledged_at timestamptz NOT NULL DEFAULT now(),

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT ux_pledges_to_vote_election_subscriber UNIQUE (election_id, subscriber_id)
      )
    SQL

    add_index "warehouse.pledges_to_vote", [ :election_id, :region ],
      name: "idx_pledges_to_vote_election_region"
    add_index "warehouse.pledges_to_vote", :pledged_at, name: "idx_pledges_to_vote_pledged_at"
    add_index "warehouse.pledges_to_vote", :subscriber_id, name: "idx_pledges_to_vote_subscriber"
  end

  def down
    drop_table "warehouse.pledges_to_vote"
  end
end
