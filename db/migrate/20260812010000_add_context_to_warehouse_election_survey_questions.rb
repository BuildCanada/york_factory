class AddContextToWarehouseElectionSurveyQuestions < ActiveRecord::Migration[8.1]
  # Background a voter needs before they can answer.
  #
  # Distinct from `help`, which is form guidance about the field itself ("We'll
  # send you the results for your ward"). This is editorial: what the city is
  # already doing, what the trade-off actually is, which powers Toronto does and
  # doesn't hold. Several of these questions are unanswerable without it — "the
  # Toronto Police Service budget should:" means very little to someone who
  # doesn't know the budget rose in 2026 and why.
  #
  # Optional, and long-form: a paragraph or two, so `text` rather than
  # `varchar`. Questions without it — postal code, ward, email — simply carry
  # null, and the tracker omits the block entirely rather than rendering an
  # empty one.
  def change
    add_column "warehouse.election_survey_questions", :context, :text
  end
end
