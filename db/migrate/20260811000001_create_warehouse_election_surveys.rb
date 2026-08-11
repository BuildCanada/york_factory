class CreateWarehouseElectionSurveys < ActiveRecord::Migration[8.1]
  # The survey definitions themselves — the questions, not the answers.
  #
  # These used to live in the tracker (surveyData.ts), which was deliberate:
  # rewording a question or adding an option needed no migration here. They move
  # because candidates now answer surveys too, and an admin-entered candidate
  # questionnaire has to render the question set as a form in this app's CMS.
  # A question set that only exists in the front end can't do that.
  #
  # One row per survey per election, so an election can hold several: Toronto
  # 2026 has `city-priorities` (residents) and `candidate-questionnaire`
  # (candidates). `audience` records which kind of respondent a survey is for,
  # and is what keeps the resident form from ever rendering candidate questions.
  #
  # Questions are rows rather than one jsonb document on the survey. The CMS
  # edits one question at a time and reorders them; a document would make every
  # edit a read-modify-write of the whole survey and give up per-field
  # validation. Options stay jsonb on the question — they are ordered
  # {value,label,detail} triples with no identity of their own, and nothing
  # queries inside them.
  AUDIENCES = %w[resident candidate].freeze

  QUESTION_TYPES = %w[text email textarea select radio yesno].freeze

  def up
    execute <<~SQL
      CREATE TABLE warehouse.election_surveys (
        id bigserial PRIMARY KEY,
        election_id bigint NOT NULL REFERENCES warehouse.elections(id) ON DELETE CASCADE,
        slug varchar NOT NULL,
        audience varchar NOT NULL DEFAULT 'resident',
        version varchar NOT NULL DEFAULT '1',

        -- Page furniture: title, intro, submit label, thank-you copy. Prose
        -- with no structure worth columns, and the tracker is the only reader.
        meta jsonb NOT NULL DEFAULT '{}'::jsonb,

        -- Null until the survey is ready to be served. The public API only
        -- returns published surveys, so a half-authored candidate
        -- questionnaire can sit in the CMS without appearing on the site.
        published_at timestamptz,

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT ux_election_surveys_slug UNIQUE (election_id, slug),
        CONSTRAINT election_surveys_audience_check
          CHECK (audience IN (#{AUDIENCES.map { |a| "'#{a}'" }.join(',')}))
      )
    SQL

    execute <<~SQL
      CREATE TABLE warehouse.election_survey_questions (
        id bigserial PRIMARY KEY,
        election_survey_id bigint NOT NULL
          REFERENCES warehouse.election_surveys(id) ON DELETE CASCADE,

        -- The payload key. Answers are stored keyed by this, so it is the one
        -- value here that must not change once responses exist: renaming it
        -- orphans every answer already collected. The CMS should treat it as
        -- read-only after the survey is published.
        question_id varchar NOT NULL,

        -- Steps are denormalised onto the question rather than given their own
        -- table. A step is a title, an optional intro and an order — it has no
        -- behaviour and nothing references it, so a table would buy only the
        -- guarantee that two questions in one step agree on its title, at the
        -- cost of a third level of CRUD in the CMS. The API groups by
        -- (step_position, step_id) on the way out.
        step_id varchar NOT NULL,
        step_title varchar NOT NULL,
        step_intro text,
        step_position integer NOT NULL DEFAULT 0,

        position integer NOT NULL DEFAULT 0,

        -- `question_type`, not `type`: ActiveRecord reserves a `type` column for
        -- single-table inheritance and raises SubclassNotFound on every read
        -- ("failed to locate the subclass: 'text'"). Serialised back to `type`
        -- for the tracker, whose renderer keys off that name.
        question_type varchar NOT NULL,
        label text NOT NULL,
        help text,
        topic varchar,
        placeholder varchar,
        required boolean NOT NULL DEFAULT false,
        rows integer,

        -- Ordered [{value,label,detail}] for select and radio; empty otherwise.
        options jsonb NOT NULL DEFAULT '[]'::jsonb,

        -- Set to 'wards' where the choices are the election's council wards.
        -- Those are resolved from the ward boundaries when the survey is
        -- served, so the list cannot drift from the ward map and ward pages the
        -- way a frozen copy in `options` would. Null means `options` is literal.
        options_source varchar,

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT ux_election_survey_questions_qid
          UNIQUE (election_survey_id, question_id),
        CONSTRAINT election_survey_questions_type_check
          CHECK (question_type IN (#{QUESTION_TYPES.map { |t| "'#{t}'" }.join(',')}))
      )
    SQL

    add_index "warehouse.election_surveys", [ :election_id, :audience ],
      name: "idx_election_surveys_election_audience"
    # The read path: every question for one survey, already in render order.
    add_index "warehouse.election_survey_questions",
      [ :election_survey_id, :step_position, :position ],
      name: "idx_election_survey_questions_order"
  end

  def down
    drop_table "warehouse.election_survey_questions"
    drop_table "warehouse.election_surveys"
  end
end
