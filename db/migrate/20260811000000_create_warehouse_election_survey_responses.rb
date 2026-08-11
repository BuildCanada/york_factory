class CreateWarehouseElectionSurveyResponses < ActiveRecord::Migration[8.1]
  # Resident survey submissions from the election tracker, one per subscriber
  # per survey per election: who answered (subscriber upserted by email, same
  # low-friction pattern as the newsletter signup and the vote pledge), which
  # survey of which election, and what they said.
  #
  # `answers` is jsonb keyed by the question ids the front end defines, rather
  # than a column per question. The question set lives in the tracker
  # (surveyData.ts) and is meant to be edited freely — rewording a question or
  # adding an option must not need a migration here. `survey_version` records
  # which question set a row answered so responses stay interpretable across
  # those edits.
  #
  # Two ward columns on purpose: `region` is what the respondent picked, and
  # `derived_region` is what their postal code resolves to via
  # Warehouse::BoundaryLookup. Neither is authoritative alone — a postal
  # centroid near a ward line resolves to the neighbour — so keeping both lets
  # results be cut either way, and makes the disagreement rate measurable.
  def up
    execute <<~SQL
      CREATE TABLE warehouse.election_survey_responses (
        id bigserial PRIMARY KEY,
        election_id bigint NOT NULL REFERENCES warehouse.elections(id) ON DELETE CASCADE,
        subscriber_id bigint NOT NULL REFERENCES public.subscribers(id) ON DELETE CASCADE,
        survey_slug varchar NOT NULL,
        survey_version varchar,
        answers jsonb NOT NULL DEFAULT '{}'::jsonb,
        region varchar,
        derived_region varchar,
        postal_code varchar(7),
        submitted_at timestamptz NOT NULL DEFAULT now(),

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT ux_election_survey_responses_subscriber
          UNIQUE (election_id, subscriber_id, survey_slug)
      )
    SQL

    add_index "warehouse.election_survey_responses", [ :election_id, :survey_slug ],
      name: "idx_election_survey_responses_election_survey"
    add_index "warehouse.election_survey_responses", [ :election_id, :derived_region ],
      name: "idx_election_survey_responses_election_derived_region"
    add_index "warehouse.election_survey_responses", :submitted_at,
      name: "idx_election_survey_responses_submitted_at"
    add_index "warehouse.election_survey_responses", :subscriber_id,
      name: "idx_election_survey_responses_subscriber"
    # Tallies group by answer value, which means reading inside the document.
    add_index "warehouse.election_survey_responses", :answers,
      using: :gin, name: "idx_election_survey_responses_answers"
  end

  def down
    drop_table "warehouse.election_survey_responses"
  end
end
