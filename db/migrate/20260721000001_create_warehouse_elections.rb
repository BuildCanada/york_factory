class CreateWarehouseElections < ActiveRecord::Migration[8.1]
  # Elections in any jurisdiction (starting with Toronto's 2026 municipal
  # election), the races they contain (mayor at-large, councillor per ward,
  # trustee per school-board ward, and later MP/MPP per riding), and the
  # registered candidates in each race.
  KINDS = %w[municipal provincial federal by_election].freeze
  OFFICE_TYPES = %w[mayor councillor trustee mp mpp].freeze
  DISTRICT_TYPES = %w[at_large ward school_board_ward riding district].freeze
  CANDIDATE_STATUSES = %w[active withdrawn].freeze

  def up
    execute <<~SQL
      CREATE TABLE warehouse.elections (
        id bigserial PRIMARY KEY,
        jurisdiction_id bigint NOT NULL REFERENCES warehouse.jurisdictions(id),
        name varchar NOT NULL,
        slug varchar NOT NULL,
        kind varchar NOT NULL DEFAULT 'municipal',
        election_date date NOT NULL,
        nomination_close_date date,

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT elections_kind_check
          CHECK (kind IN (#{KINDS.map { |s| "'#{s}'" }.join(',')}))
      )
    SQL
    add_index "warehouse.elections", :slug, unique: true, name: "ux_elections_slug"
    add_index "warehouse.elections", :jurisdiction_id, name: "idx_elections_jurisdiction"

    execute <<~SQL
      CREATE TABLE warehouse.election_races (
        id bigserial PRIMARY KEY,
        election_id bigint NOT NULL REFERENCES warehouse.elections(id) ON DELETE CASCADE,
        office_type varchar NOT NULL,
        district_type varchar NOT NULL DEFAULT 'at_large',
        district_number integer,
        district_name varchar,
        office_body varchar,
        metadata jsonb NOT NULL DEFAULT '{}',

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT election_races_office_type_check
          CHECK (office_type IN (#{OFFICE_TYPES.map { |s| "'#{s}'" }.join(',')})),
        CONSTRAINT election_races_district_type_check
          CHECK (district_type IN (#{DISTRICT_TYPES.map { |s| "'#{s}'" }.join(',')}))
      )
    SQL
    # COALESCE folds NULL office_body/district_number (mayor, at-large races)
    # into the key so Postgres's NULLs-are-distinct rule can't allow duplicates.
    execute <<~SQL
      CREATE UNIQUE INDEX ux_election_races_identity
        ON warehouse.election_races
        (election_id, office_type, COALESCE(office_body, ''), COALESCE(district_number, 0))
    SQL

    execute <<~SQL
      CREATE TABLE warehouse.election_candidates (
        id bigserial PRIMARY KEY,
        election_race_id bigint NOT NULL REFERENCES warehouse.election_races(id) ON DELETE CASCADE,
        full_name varchar NOT NULL,
        first_name varchar,
        last_name varchar,
        status varchar NOT NULL DEFAULT 'active',
        nomination_date date,
        withdrawn_date date,
        email varchar,
        phone varchar,
        website varchar,
        social_links jsonb NOT NULL DEFAULT '[]',
        last_seen_at timestamptz,

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT election_candidates_status_check
          CHECK (status IN (#{CANDIDATE_STATUSES.map { |s| "'#{s}'" }.join(',')}))
      )
    SQL
    add_index "warehouse.election_candidates", [ :election_race_id, :full_name ],
      unique: true, name: "ux_election_candidates_race_name"
    add_index "warehouse.election_candidates", :status, name: "idx_election_candidates_status"
  end

  def down
    drop_table "warehouse.election_candidates"
    drop_table "warehouse.election_races"
    drop_table "warehouse.elections"
  end
end
