# A candidate's answers to an election questionnaire, entered by staff.
#
# Separate from Warehouse::ElectionSurveyResponse (residents) because the two
# differ in every way that matters: residents are anonymous subscribers whose
# answers are published only in aggregate and replaced silently on
# re-submission, while a candidate's answers are attributed public statements
# about what they will do in office.
#
# There is no public write path — see the migration. `source` and `entered_by`
# record how the answers were obtained and by whom, so a published position is
# always traceable.
class Warehouse::ElectionCandidateSurveyResponse < Warehouse::Record
  self.table_name = "warehouse.election_candidate_survey_responses"

  # Structural limits, mirroring Warehouse::ElectionSurveyResponse. Unlike the
  # resident table these answers CAN be checked against the question set, since
  # the questions now live here too — see #answers_match_the_survey.
  MAX_ANSWERS = 100
  MAX_KEY_LENGTH = 64
  MAX_VALUE_LENGTH = 2_000
  MAX_EXPLANATION_LENGTH = 5_000

  belongs_to :survey,
    class_name: "Warehouse::ElectionSurvey",
    foreign_key: :election_survey_id,
    inverse_of: :candidate_responses
  belongs_to :candidate,
    class_name: "Warehouse::ElectionCandidate",
    foreign_key: :election_candidate_id,
    inverse_of: :survey_responses

  enum :status, { draft: "draft", submitted: "submitted", published: "published" }
  enum :source, {
    admin: "admin", email: "email", form: "form", phone: "phone", other: "other"
  }, prefix: :via

  validates :election_candidate_id, uniqueness: { scope: :election_survey_id }
  validate :answers_are_well_formed
  validate :explanations_are_well_formed
  validate :answers_match_the_survey
  validate :candidate_is_in_this_election
  validate :published_has_a_timestamp

  # Publishing stamps the time if the caller didn't; the CHECK constraint in the
  # migration refuses the row otherwise, and a validation error there would
  # surface as a 500 rather than a form error.
  before_validation :stamp_published_at

  scope :published, -> { where(status: "published").where.not(published_at: nil) }

  # Answers for one question id across a scope, as {value => count}. Same shape
  # and the same naming trap as the resident version: a class method called
  # `tally` is shadowed by Enumerable#tally on a Relation and never reached.
  def self.tally_answers(question_id)
    where("answers ? :key", key: question_id)
      .group("answers ->> #{connection.quote(question_id)}")
      .count
  end

  # Which of the survey's questions this candidate has not answered. Staff enter
  # these by hand from replies that are often partial, so an incomplete response
  # is normal and worth surfacing in the CMS rather than rejecting.
  def unanswered_question_ids
    survey.questions.map(&:question_id) - answers.keys
  end

  private

  def stamp_published_at
    self.published_at ||= Time.current if status == "published"
  end

  def answers_are_well_formed
    unless answers.is_a?(Hash)
      errors.add(:answers, "must be an object")
      return
    end

    errors.add(:answers, "has too many entries") if answers.size > MAX_ANSWERS

    answers.each do |key, value|
      errors.add(:answers, "has an over-long key") if key.to_s.length > MAX_KEY_LENGTH
      unless value.is_a?(String)
        errors.add(:answers, "must map every question to a string")
        next
      end
      errors.add(:answers, "has an over-long value") if value.length > MAX_VALUE_LENGTH
    end
  end

  def explanations_are_well_formed
    unless explanations.is_a?(Hash)
      errors.add(:explanations, "must be an object")
      return
    end

    explanations.each do |key, value|
      errors.add(:explanations, "has an over-long key") if key.to_s.length > MAX_KEY_LENGTH
      unless value.is_a?(String)
        errors.add(:explanations, "must map every question to a string")
        next
      end
      if value.length > MAX_EXPLANATION_LENGTH
        errors.add(:explanations, "has an over-long entry")
      end
    end
  end

  # Because the questions live in this app now, an answer keyed to a question
  # that doesn't exist is a mistake we can catch rather than store. Applied to
  # candidate responses only: these are typed in by hand, where a stale
  # question_id is a plausible slip, and there is no unauthenticated caller for
  # this to reject unfairly.
  #
  # Only the key is checked, not the value. Staff transcribe what candidates
  # actually say, which is not always one of the offered options, and refusing
  # "supports with caveats" would mean either losing the nuance or not recording
  # the response at all.
  def answers_match_the_survey
    return if survey.blank?

    known = survey.questions.map(&:question_id).to_set
    return if known.empty?

    unknown = (answers.keys.to_set + explanations.keys.to_set) - known
    return if unknown.empty?

    errors.add(:answers, "reference questions not in this survey: #{unknown.to_a.sort.join(', ')}")
  end

  # A candidate can only answer a survey belonging to the election they are
  # standing in. Nothing in the foreign keys prevents attaching a Brampton
  # candidate to a Toronto questionnaire, and doing so would publish a position
  # under the wrong race.
  def candidate_is_in_this_election
    return if survey.blank? || candidate.blank?

    candidate_election_id = candidate.race&.election_id
    return if candidate_election_id.blank?
    return if candidate_election_id == survey.election_id

    errors.add(:candidate, "is not standing in this survey's election")
  end

  def published_has_a_timestamp
    return unless status == "published"

    errors.add(:published_at, "is required to publish") if published_at.blank?
  end
end
