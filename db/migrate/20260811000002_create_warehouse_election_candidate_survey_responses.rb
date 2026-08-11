class CreateWarehouseElectionCandidateSurveyResponses < ActiveRecord::Migration[8.1]
  # A candidate's answers to an election questionnaire.
  #
  # Deliberately a separate table from warehouse.election_survey_responses
  # rather than that table with a nullable respondent, because the two are
  # different records that happen to share a shape:
  #
  #   resident  — a Subscriber upserted by email, self-serve, published only as
  #               an anonymous aggregate, replaced silently on re-submission.
  #   candidate — a known roster row, entered by staff, published attributed by
  #               name, and a change to a published position is a fact about the
  #               campaign that we keep rather than overwrite.
  #
  # There is no public write path. Candidate answers are attributed public
  # statements, and warehouse.election_candidates carries an `email`, so an
  # endpoint keyed on candidate email would let anyone publish positions in a
  # candidate's name. Staff enter these through the CMS from whatever the
  # candidate sends back, which is why `source` and `entered_by` exist: a
  # published position must always be traceable to how it was obtained.
  #
  # `answers` matches the resident table — jsonb keyed by question_id — so the
  # same tally helpers work. `explanations` is separate rather than folded in
  # because a candidate's prose is published verbatim next to their choice,
  # while answers are what gets tallied; keeping them apart means the tally
  # queries never have to tell an option value from a paragraph.
  STATUSES = %w[draft submitted published].freeze

  SOURCES = %w[admin email form phone other].freeze

  def up
    execute <<~SQL
      CREATE TABLE warehouse.election_candidate_survey_responses (
        id bigserial PRIMARY KEY,
        election_survey_id bigint NOT NULL
          REFERENCES warehouse.election_surveys(id) ON DELETE CASCADE,
        election_candidate_id bigint NOT NULL
          REFERENCES warehouse.election_candidates(id) ON DELETE CASCADE,

        survey_version varchar,
        answers jsonb NOT NULL DEFAULT '{}'::jsonb,

        -- {question_id => prose}. Published verbatim beside the answer.
        explanations jsonb NOT NULL DEFAULT '{}'::jsonb,

        status varchar NOT NULL DEFAULT 'draft',

        -- How the candidate's answers reached us, and which staff member
        -- entered them. Without these a published position is unattributable.
        source varchar NOT NULL DEFAULT 'admin',
        entered_by varchar,

        -- Free-text staff note: caveats, partial responses, what was chased.
        notes text,

        submitted_at timestamptz,
        published_at timestamptz,

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT ux_election_candidate_survey_responses
          UNIQUE (election_survey_id, election_candidate_id),
        CONSTRAINT election_candidate_survey_responses_status_check
          CHECK (status IN (#{STATUSES.map { |s| "'#{s}'" }.join(',')})),
        CONSTRAINT election_candidate_survey_responses_source_check
          CHECK (source IN (#{SOURCES.map { |s| "'#{s}'" }.join(',')})),
        -- A published response must record when. Enforced here because the
        -- public API filters on published_at, so a published row with a null
        -- timestamp would be invisible on the site while reading as live in
        -- the CMS — the kind of mismatch that gets noticed late.
        CONSTRAINT election_candidate_survey_responses_published_at
          CHECK (status <> 'published' OR published_at IS NOT NULL)
      )
    SQL

    add_index "warehouse.election_candidate_survey_responses",
      [ :election_survey_id, :status ],
      name: "idx_candidate_survey_responses_survey_status"
    add_index "warehouse.election_candidate_survey_responses",
      :election_candidate_id,
      name: "idx_candidate_survey_responses_candidate"
    # Tallies group by answer value, which means reading inside the document.
    add_index "warehouse.election_candidate_survey_responses", :answers,
      using: :gin, name: "idx_candidate_survey_responses_answers"
  end

  def down
    drop_table "warehouse.election_candidate_survey_responses"
  end
end
