class Warehouse::Election < Warehouse::Record
  belongs_to :jurisdiction

  # Postal-code residency check for "I pledge to vote" submissions.
  has_object :pledge_eligibility
  has_many :races, class_name: "Warehouse::ElectionRace", dependent: :destroy
  has_many :candidates, through: :races
  has_many :pledges_to_vote, class_name: "Warehouse::PledgeToVote", dependent: :destroy

  enum :kind, {
    municipal: "municipal",
    provincial: "provincial",
    federal: "federal",
    by_election: "by_election"
  }

  validates :name, :slug, :election_date, presence: true
  validates :slug, uniqueness: true
end
