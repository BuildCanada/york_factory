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
end
