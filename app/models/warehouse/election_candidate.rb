class Warehouse::ElectionCandidate < Warehouse::Record
  belongs_to :race, class_name: "Warehouse::ElectionRace",
    foreign_key: :election_race_id, inverse_of: :candidates

  # Admin-reviewed portrait; photo_source/photo_attribution track provenance
  # and photo_suggestions holds machine-collected candidates for review.
  has_one_attached :photo
  has_object :photo_suggester

  # Questionnaire answers, entered by staff — never self-serve. See
  # Warehouse::ElectionCandidateSurveyResponse.
  has_many :survey_responses,
    class_name: "Warehouse::ElectionCandidateSurveyResponse",
    foreign_key: :election_candidate_id,
    inverse_of: :candidate,
    dependent: :destroy

  enum :status, { active: "active", withdrawn: "withdrawn" }

  validates :full_name, presence: true, uniqueness: { scope: :election_race_id }

  def display_name
    return "#{first_name} #{last_name}" if first_name.present? && last_name.present?

    full_name
  end
end
