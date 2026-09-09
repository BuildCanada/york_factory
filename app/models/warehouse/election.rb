class Warehouse::Election < Warehouse::Record
  # published_at gates public visibility: an election is built up in admin
  # (races, then candidates) and only reaches the API once published. Regions
  # whose candidates are entered by hand need that runway.
  include Publishable

  belongs_to :jurisdiction

  # Postal-code residency check for "I pledge to vote" submissions.
  has_object :pledge_eligibility
  has_many :races, class_name: "Warehouse::ElectionRace", dependent: :destroy
  has_many :candidates, through: :races
  has_many :pledges_to_vote, class_name: "Warehouse::PledgeToVote", dependent: :destroy
  has_many :survey_responses, class_name: "Warehouse::ElectionSurveyResponse", dependent: :destroy
  # The survey definitions — the questions themselves. Resident and candidate
  # surveys are separate rows with independent question sets, told apart by
  # `audience`.
  has_many :surveys, class_name: "Warehouse::ElectionSurvey", dependent: :destroy

  enum :kind, {
    municipal: "municipal",
    provincial: "provincial",
    federal: "federal",
    by_election: "by_election"
  }

  validates :name, :slug, :election_date, presence: true
  validates :slug, uniqueness: true

  # Choices for every survey question that defers to this election for its
  # options, keyed by options_source — see
  # Warehouse::ElectionSurveyQuestion#options_for.
  def survey_option_sources
    {
      "wards" => ward_options,
      "mayoral_candidates" => mayoral_candidate_options
    }
  end

  # Ward choices for survey questions whose options_source is "wards", as
  # [{value,label}] — e.g. {"value" => "ward-1", "label" => "1 — Etobicoke North"}.
  #
  # Read from the councillor races rather than the ward boundaries, because the
  # races are what the tracker's ward pages and the candidate roster are built
  # from. A survey offering a ward with no council race would send a resident to
  # a ward page that doesn't exist.
  def ward_options
    races.where(office_type: "councillor", district_type: "ward")
      .where.not(district_number: nil)
      .order(:district_number)
      .map do |race|
        number = race.district_number.to_i
        label = race.district_name.presence ? "#{number} — #{race.district_name}" : number.to_s
        { "value" => "ward-#{number}", "label" => label }
      end
  end

  # Mayoral-ballot choices for survey questions whose options_source is
  # "mayoral_candidates", as [{value,label}] — e.g.
  # {"value" => "olivia-chow", "label" => "Olivia Chow"}.
  #
  # Withdrawn candidates are left out: a vote-intention question should offer
  # the ballot as it will be, not everyone who ever registered. The value is the
  # parameterized name rather than the row id so a tally stays readable and
  # survives a reseed of the candidate tables, which the scrapers rewrite — and
  # is deduplicated for the same reason, since two rows that parameterize alike
  # would render as two identical choices holding one tally between them.
  #
  # Ordered by surname, the order the name appears in on an Ontario ballot.
  def mayoral_candidate_options
    candidates.active
      .where(election_race_id: races.where(office_type: "mayor").select(:id))
      .sort_by { |candidate| [ candidate.sort_name, candidate.display_name ] }
      .map { |candidate| { "value" => candidate.display_name.parameterize, "label" => candidate.display_name } }
      .uniq { |option| option["value"] }
  end
end
