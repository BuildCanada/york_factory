# One resident-survey submission from the election tracker: the subscriber who
# answered (upserted by email, same pattern as the newsletter signup and the
# vote pledge), the election and survey it belongs to, and the answers.
#
# One response per subscriber per survey per election — re-submitting updates
# the answers and the timestamp rather than adding a row, so tallies count
# people rather than submissions.
class Warehouse::ElectionSurveyResponse < Warehouse::Record
  self.table_name = "warehouse.election_survey_responses"

  # Structural limits only. The question set lives in the tracker and is meant
  # to change without a deploy here, so this validates the *shape* of a
  # submission — enough to keep junk and unbounded payloads out of the column —
  # and never which questions exist or what a valid answer to one is. A
  # question renamed in the tracker must not start failing validation here.
  MAX_ANSWERS = 100
  MAX_KEY_LENGTH = 64
  MAX_VALUE_LENGTH = 2_000

  belongs_to :election
  belongs_to :subscriber, class_name: "::Subscriber"

  validates :survey_slug, presence: true, length: { maximum: 100 }
  validates :submitted_at, presence: true
  validates :subscriber_id, uniqueness: { scope: [ :election_id, :survey_slug ] }
  validate :answers_are_well_formed

  before_validation { self.submitted_at ||= Time.current }

  # Answers for one question id across a scope, as {value => count}. Used to
  # publish results; skips rows that never answered that question.
  #
  # Named `tally_answers`, not `tally`: Relation includes Enumerable, so a
  # class method called `tally` is shadowed by Enumerable#tally and silently
  # never reached from a scope.
  def self.tally_answers(question_id)
    where("answers ? :key", key: question_id)
      .group("answers ->> #{connection.quote(question_id)}")
      .count
  end

  private

  def answers_are_well_formed
    unless answers.is_a?(Hash)
      errors.add(:answers, "must be an object")
      return
    end

    errors.add(:answers, "has too many entries") if answers.size > MAX_ANSWERS

    answers.each do |key, value|
      errors.add(:answers, "has an over-long key") if key.to_s.length > MAX_KEY_LENGTH
      # Every answer the form produces is a string (including "yes"/"no" and
      # the select values); anything else means the client sent something we
      # didn't design for, and storing it would break the tally queries.
      unless value.is_a?(String)
        errors.add(:answers, "must map every question to a string")
        next
      end
      errors.add(:answers, "has an over-long value") if value.length > MAX_VALUE_LENGTH
    end
  end
end
