# One "I pledge to vote" submission: the subscriber who pledged (upserted by
# email, same pattern as the newsletter signup), the election, the region of
# it the pledge is for (e.g. "ward-5" for a Toronto ward, or the
# jurisdiction slug for a city-wide pledge), and when it was made. One pledge
# per subscriber per election — re-pledging updates the region and timestamp.
class Warehouse::PledgeToVote < Warehouse::Record
  self.table_name = "warehouse.pledges_to_vote"

  belongs_to :election
  belongs_to :subscriber, class_name: "::Subscriber"

  validates :region, presence: true, length: { maximum: 100 }
  validates :pledged_at, presence: true
  validates :subscriber_id, uniqueness: { scope: :election_id }

  before_validation { self.pledged_at ||= Time.current }
  before_create :generate_share_token

  private

  # Public identifier for the pledge's shareable page — random rather than
  # the sequential id so pledge URLs can't be enumerated.
  def generate_share_token
    self.share_token ||= loop do
      token = SecureRandom.alphanumeric(10).downcase
      break token unless self.class.exists?(share_token: token)
    end
  end
end
