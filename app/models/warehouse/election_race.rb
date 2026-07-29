# One contest within an election: the at-large mayoral race, a councillor
# race in a ward, a trustee race in a school-board ward (office_body names
# the board), or later an MP/MPP race in a riding.
class Warehouse::ElectionRace < Warehouse::Record
  belongs_to :election
  has_many :candidates, class_name: "Warehouse::ElectionCandidate",
    foreign_key: :election_race_id, inverse_of: :race, dependent: :destroy

  enum :office_type, {
    mayor: "mayor",
    councillor: "councillor",
    trustee: "trustee",
    mp: "mp",
    mpp: "mpp"
  }

  enum :district_type, {
    at_large: "at_large",
    ward: "ward",
    school_board_ward: "school_board_ward",
    riding: "riding",
    district: "district"
  }, suffix: true

  validates :office_type, :district_type, presence: true
  # Mirrors ux_election_races_identity so a hand-entered duplicate reports a
  # validation error instead of a database exception.
  validates :office_type, uniqueness: {
    scope: %i[election_id office_body district_number],
    message: "already has a race for this body and district"
  }

  # Mayor first, then councillor districts in order, then trustees by board.
  # Shared by the public API and the admin screens so both read the same way.
  def self.sorted(races)
    races.sort_by do |race|
      [ office_types.keys.index(race.office_type).to_i, race.office_body.to_s, race.district_number.to_i ]
    end
  end

  # "Wards 1, 5" where the source names the district, "Ward 3" where only the
  # number is known, nil for an at-large race.
  def district_label
    district_name.presence || (district_number && "Ward #{district_number}")
  end

  # Heading for one race: "Mayor", "Councillor — Ward 3",
  # "Trustee — Peel District School Board, Wards 1, 5".
  def label
    scope = [ office_body.presence, district_label ].compact.join(", ")
    scope.present? ? "#{office_type.titleize} — #{scope}" : office_type.titleize
  end
end
