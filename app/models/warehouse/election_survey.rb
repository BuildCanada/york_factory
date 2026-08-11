# One survey belonging to an election: its slug, who it is asked of, and its
# questions. The definition, not the answers.
#
# An election can hold several — Toronto 2026 has `city-priorities` for
# residents and `candidate-questionnaire` for candidates. The two are
# independent question sets with their own ids; nothing here assumes a question
# in one has a counterpart in the other.
class Warehouse::ElectionSurvey < Warehouse::Record
  self.table_name = "warehouse.election_surveys"

  AUDIENCES = %w[resident candidate].freeze

  belongs_to :election, class_name: "Warehouse::Election"

  has_many :questions,
    -> { ordered },
    class_name: "Warehouse::ElectionSurveyQuestion",
    foreign_key: :election_survey_id,
    inverse_of: :survey,
    dependent: :destroy

  has_many :candidate_responses,
    class_name: "Warehouse::ElectionCandidateSurveyResponse",
    foreign_key: :election_survey_id,
    inverse_of: :survey,
    dependent: :destroy

  enum :audience, { resident: "resident", candidate: "candidate" }

  validates :slug, presence: true,
    format: { with: /\A[a-z0-9-]{1,100}\z/, message: "must be lowercase, digits and dashes" },
    uniqueness: { scope: :election_id }
  validates :version, presence: true, length: { maximum: 50 }
  validate :meta_is_an_object

  scope :published, -> { where.not(published_at: nil) }

  def published?
    published_at.present?
  end

  # The survey as the tracker renders it: questions grouped into steps, in
  # order. Shaped here rather than in the serializer because both the public API
  # and the CMS questionnaire form need the same grouping, and the grouping is a
  # property of the survey (step_position, then position) rather than of either
  # caller.
  #
  # `ward_options` supplies the choices for questions whose options_source is
  # "wards" — see ElectionSurveyQuestion#options_for. It is passed in rather
  # than looked up here so this stays a pure read with no boundary dependency.
  def steps(ward_options: [])
    questions.group_by { |q| [ q.step_position, q.step_id ] }
      .sort_by { |(step_position, step_id), _| [ step_position, step_id ] }
      .map do |(_, step_id), grouped|
        first = grouped.first
        {
          id: step_id,
          title: first.step_title,
          intro: first.step_intro.presence,
          questions: grouped.map { |q| q.as_definition(ward_options: ward_options) }
        }.compact
      end
  end

  private

  def meta_is_an_object
    errors.add(:meta, "must be an object") unless meta.is_a?(Hash)
  end
end
